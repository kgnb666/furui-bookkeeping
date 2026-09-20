package com.campus.ledger.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campus.ledger.entity.Budget;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface BudgetMapper extends BaseMapper<Budget> {
}
