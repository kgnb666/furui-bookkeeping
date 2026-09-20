package com.example.campus_ledger

import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

/**
 * 常驻通知要显示的一组数字。
 *
 * 金额一律用「分」表示，避免 double 参与金额运算（与项目其它部分的规范一致）。
 * 数据全部来自已有接口，本功能不需要后端做任何改动。
 */
data class LedgerSnapshot(
    val todayExpenseCents: Long,
    val todayIncomeCents: Long,
    val monthExpenseCents: Long,
    val monthBalanceCents: Long,
    /** 月度总预算金额；未设置预算时为 null */
    val budgetCents: Long?,
    val budgetUsedCents: Long,
    /** 预算使用率（百分数，如 132.06）；未设置预算时为 null */
    val usageRate: Double?,
)

/** 读取常驻通知所需数据的极简 HTTP 客户端，只用 JDK/Android 自带能力，不引第三方库。 */
object LedgerApi {

    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 15_000

    /** 一次抓齐三个接口；任一失败都直接抛出，由调用方决定如何展示。 */
    fun fetch(baseUrl: String, token: String, month: String): LedgerSnapshot {
        val base = baseUrl.trimEnd('/')

        val daily = getData("$base/statistics/daily-summary", token)
        val monthly = getData("$base/statistics/monthly?month=$month", token)
        val budgets = getData("$base/budgets?month=$month", token)

        val total = budgets.optJSONObject("total")
        val budgetCents = total?.let { cents(it.optString("amount")) }
        val usedCents = total?.let { cents(it.optString("used")) } ?: 0L
        val rate = total?.let {
            it.optString("usageRate").takeIf { s -> s.isNotBlank() }?.toDoubleOrNull()
        }

        return LedgerSnapshot(
            todayExpenseCents = cents(daily.optString("expense")),
            todayIncomeCents = cents(daily.optString("income")),
            monthExpenseCents = cents(monthly.optString("expense")),
            monthBalanceCents = cents(monthly.optString("balance")),
            budgetCents = budgetCents,
            budgetUsedCents = usedCents,
            usageRate = rate,
        )
    }

    /** 取统一响应体里的 data 字段；code 非 0 或 HTTP 非 2xx 时抛异常。 */
    private fun getData(url: String, token: String): JSONObject {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            val status = connection.responseCode
            val body = (if (status in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                ?: throw LedgerApiException("HTTP $status")

            val json = JSONObject(body)
            if (status !in 200..299 || json.optInt("code", -1) != 0) {
                throw LedgerApiException(json.optString("message").ifBlank { "HTTP $status" }, status)
            }
            return json.getJSONObject("data")
        } catch (e: LedgerApiException) {
            throw e
        } catch (e: Exception) {
            throw LedgerApiException(e.message ?: "网络异常")
        } finally {
            connection.disconnect()
        }
    }

    /** "1238.33" -> 123833，四舍五入到分；解析不了时返回 0。 */
    private fun cents(value: String?): Long {
        if (value.isNullOrBlank()) return 0L
        return try {
            BigDecimal(value).multiply(BigDecimal(100)).setScale(0, RoundingMode.HALF_UP).toLong()
        } catch (_: NumberFormatException) {
            0L
        }
    }

    /**
     * 当前月份，格式 yyyy-MM。
     * 这里用 Calendar 而不是 java.time：minSdk 是 24，而 java.time 需要 API 26
     * 或者开启 core library desugaring，为一个小功能引入 desugar 依赖不划算。
     */
    fun currentMonth(): String {
        val now = Calendar.getInstance()
        return "%04d-%02d".format(
            now.get(Calendar.YEAR),
            now.get(Calendar.MONTH) + 1,
        )
    }
}

/** 取数失败时抛出，携带 HTTP 状态码方便区分「登录过期」和「网络不通」。 */
class LedgerApiException(message: String, val statusCode: Int = 0) : Exception(message)
