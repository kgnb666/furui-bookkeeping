package com.example.campus_ledger

import android.content.Context

/**
 * 常驻通知的本地配置。
 *
 * 单独存一份 token 与接口地址，而不是去读 shared_preferences 插件写的文件——
 * 插件内部的文件名和 key 前缀属于实现细节，直接依赖容易在升级后失效。
 * 每次 Flutter 侧刷新数据时会一并同步过来。
 */
class LedgerPrefs(context: Context) {

    private val prefs = context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    /** 形如 http://129.204.61.68/api，不带结尾斜杠 */
    var baseUrl: String
        get() = prefs.getString(KEY_BASE_URL, DEFAULT_BASE_URL) ?: DEFAULT_BASE_URL
        set(value) = prefs.edit().putString(KEY_BASE_URL, value.trimEnd('/')).apply()

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val FILE_NAME = "ledger_notification"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_TOKEN = "token"
        private const val KEY_BASE_URL = "base_url"
        private const val DEFAULT_BASE_URL = "http://129.204.61.68/api"
    }
}
