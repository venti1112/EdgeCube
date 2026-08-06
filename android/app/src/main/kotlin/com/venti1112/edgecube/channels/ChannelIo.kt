package com.venti1112.edgecube.channels

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * 通道处理器共用的线程辅助。
 *
 * MethodChannel 的 result 回调必须在主线程调用；耗时操作（解压、I/O、
 * 遍历目录等）放后台线程执行，完成后回主线程返回结果。
 */
internal object ChannelIo {

    val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 在后台线程执行 [block]，成功把返回值经 success 回传主线程；
     * 抛异常时按 [errorCode]（或 [errorCodeOf] 的映射结果）报错。
     * 捕获 [Throwable]：NoClassDefFoundError 等 Error 同样回传而不是让进程崩溃。
     */
    fun runAsync(
        result: MethodChannel.Result,
        errorCode: String,
        errorCodeOf: ((Throwable) -> String)? = null,
        block: () -> Any?,
    ) {
        thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Throwable) {
                val code = errorCodeOf?.invoke(e) ?: errorCode
                mainHandler.post { result.error(code, e.message, null) }
            }
        }
    }
}
