package com.campus.ledger.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.CategoryDailySum;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.ExpenseDetail;
import com.campus.ledger.dto.RecurringBillRow;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.dto.SourceSum;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.entity.Bill;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;

@Mapper
public interface BillMapper extends BaseMapper<Bill> {

    /**
     * 一次性查出这批去重键中已经存在的部分，用于导入预览时标记重复记录。
     */
    @Select("""
            <script>
            SELECT dedup_key FROM bill
            WHERE user_id = #{userId} AND dedup_key IN
            <foreach collection="dedupKeys" item="key" open="(" separator="," close=")">#{key}</foreach>
            </script>
            """)
    List<String> selectExistingDedupKeys(@Param("userId") Long userId,
                                         @Param("dedupKeys") Collection<String> dedupKeys);

    /**
     * 按月统计收入 / 支出合计（不计收支 type=3 不参与统计）。
     */
    @Select("""
            SELECT type, SUM(amount) AS amount FROM bill
            WHERE user_id = #{userId} AND type IN (1, 2)
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY type
            """)
    List<TypeSum> sumByType(@Param("userId") Long userId,
                            @Param("start") LocalDate start,
                            @Param("end") LocalDate end);

    /**
     * 按月统计各分类的支出合计，金额高的排前面。
     */
    @Select("""
            SELECT category, SUM(amount) AS amount FROM bill
            WHERE user_id = #{userId} AND type = 1
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY category
            ORDER BY SUM(amount) DESC
            """)
    List<CategorySum> sumByCategory(@Param("userId") Long userId,
                                    @Param("start") LocalDate start,
                                    @Param("end") LocalDate end);

    /**
     * 按天统计收入与支出，用于每日趋势。
     */
    @Select("""
            SELECT bill_date AS billDate, type, SUM(amount) AS amount FROM bill
            WHERE user_id = #{userId} AND type IN (1, 2)
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY bill_date, type
            ORDER BY bill_date
            """)
    List<DailySum> sumByDay(@Param("userId") Long userId,
                            @Param("start") LocalDate start,
                            @Param("end") LocalDate end);

    /**
     * 按"日期 + 分类"统计支出，用于预算预测判断某个分类本月有几天在消费。
     * 一次查询覆盖全部分类，避免按分类逐个查库。
     */
    @Select("""
            SELECT bill_date AS billDate, category AS category, SUM(amount) AS amount FROM bill
            WHERE user_id = #{userId} AND type = 1
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY bill_date, category
            ORDER BY bill_date
            """)
    List<CategoryDailySum> sumByDayAndCategory(@Param("userId") Long userId,
                                              @Param("start") LocalDate start,
                                              @Param("end") LocalDate end);

    /**
     * 按月统计各支付来源的支出合计（微信 / 支付宝 / 手动记录），金额高的排前面。
     */
    @Select("""
            SELECT source, SUM(amount) AS amount FROM bill
            WHERE user_id = #{userId} AND type = 1
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY source
            ORDER BY SUM(amount) DESC
            """)
    List<SourceSum> sumBySource(@Param("userId") Long userId,
                                @Param("start") LocalDate start,
                                @Param("end") LocalDate end);

    /**
     * 取周期识别所需的账单明细，一次查完，避免按商户逐个查库（N+1）。
     *
     * 条件固定为 user_id + type + 时间范围，走 idx_bill_user_type_date 索引；
     * 只查商户非空的记录，商户为空的账单没有分组依据，直接排除。
     * limit 用于兜住极端高频用户，避免一次拉取过多明细。
     */
    @Select("""
            SELECT merchant, category, amount, bill_date AS billDate FROM bill
            WHERE user_id = #{userId} AND type = #{type}
              AND bill_date >= #{start}
              AND merchant IS NOT NULL AND merchant <> ''
            ORDER BY bill_date DESC, id DESC
            LIMIT #{limit}
            """)
    List<RecurringBillRow> selectRecurringCandidates(@Param("userId") Long userId,
                                                    @Param("type") int type,
                                                    @Param("start") LocalDate start,
                                                    @Param("limit") int limit);

    /**
     * 按「分类 + 月份」聚合支出，一次覆盖目标月份与前 3 个月。
     *
     * 异常检测需要对比"本月 vs 前 3 个月"，用一条 SQL 把 4 个月的分组结果一起取回，
     * 避免拆成多次查询。金额与笔数都要，后者用于频次异常。
     * 走 idx_bill_user_type_date 索引。
     */
    @Select("""
            SELECT category AS category,
                   DATE_FORMAT(bill_date, #{monthPattern}) AS month,
                   SUM(amount) AS amount,
                   COUNT(*) AS count
            FROM bill
            WHERE user_id = #{userId} AND type = #{type}
              AND bill_date >= #{start} AND bill_date <= #{end}
            GROUP BY category, DATE_FORMAT(bill_date, #{monthPattern})
            """)
    List<CategoryMonthlySum> sumByCategoryAndMonth(@Param("userId") Long userId,
                                                   @Param("type") int type,
                                                   @Param("start") LocalDate start,
                                                   @Param("end") LocalDate end,
                                                   @Param("monthPattern") String monthPattern);

    /**
     * 取指定日期范围内的支出明细，用于计算同分类单笔金额的中位数基线。
     *
     * 中位数无法用 SQL 聚合直接算出，因此取回明细后在内存里排序计算；
     * 一次查完全部分类，不做按分类的循环查询（禁止 N+1）。
     * 只查商户非空之外的记录没有限制——商户为空的账单金额仍然有效，
     * 只是展示时用"分类 + 日期"定位。
     */
    @Select("""
            SELECT category AS category,
                   amount AS amount,
                   bill_date AS billDate,
                   merchant AS merchant
            FROM bill
            WHERE user_id = #{userId} AND type = #{type}
              AND bill_date >= #{start} AND bill_date <= #{end}
            ORDER BY bill_date DESC, id DESC
            LIMIT #{limit}
            """)
    List<ExpenseDetail> selectExpenseDetails(@Param("userId") Long userId,
                                             @Param("type") int type,
                                             @Param("start") LocalDate start,
                                             @Param("end") LocalDate end,
                                             @Param("limit") int limit);
}
