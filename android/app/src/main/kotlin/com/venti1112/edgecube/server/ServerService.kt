package com.venti1112.edgecube.server

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.venti1112.edgecube.MainActivity
import com.venti1112.edgecube.R

/**
 * 前台保活 Service：把服务端 JVM 进程“挂”在前台优先级下，显著降低被系统回收的概率。
 *
 * 注意：JVM 是 app 进程的子进程，前台 Service 提升的是宿主进程优先级；它不持有进程本身，
 * 进程由 [ServerProcessManager] 单例管理。Service 仅负责常驻通知与前台状态。
 */
class ServerService : Service() {

    companion object {
        private const val CHANNEL_ID = "edgecube_server"
        private const val NOTIF_ID = 1001
        const val ACTION_START = "com.venti1112.edgecube.action.START_FOREGROUND"
        const val ACTION_STOP = "com.venti1112.edgecube.action.STOP_SERVER"
        private const val EXTRA_NAME = "instance_name"

        /** 启动前台 Service 并显示常驻通知。 */
        fun start(context: Context, instanceName: String) {
            val intent = Intent(context, ServerService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_NAME, instanceName)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        /** 停止前台 Service（移除通知）。进程退出后由管理器调用。 */
        fun stop(context: Context) {
            context.stopService(Intent(context, ServerService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP ->
                // 通知上的“停止”：优雅停服；待进程退出后由管理器停止本 Service。
                ServerProcessManager.getInstance(applicationContext).stop()
            else -> {
                val name = intent?.getStringExtra(EXTRA_NAME) ?: "Minecraft 服务器"
                startInForeground(name)
            }
        }
        return START_NOT_STICKY
    }

    private fun startInForeground(name: String) {
        ensureChannel()
        val notification = buildNotification(name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "服务器运行状态",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Minecraft 服务端在后台运行时的常驻通知"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(name: String): Notification {
        val pendingFlags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            pendingFlags,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, ServerService::class.java).apply { action = ACTION_STOP },
            pendingFlags,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("服务器运行中")
            .setContentText(name)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .build()
    }
}
