package com.venti1112.edgecube.localservice

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
import com.venti1112.edgecube.MainActivity
import com.venti1112.edgecube.R

/**
 * 本地服务的前台 Service：把 App 进程挂在「前台服务」优先级下，
 * 显著降低 daemon 被系统回收的概率。
 *
 * 进程本身由 [LocalServiceManager] 单例管理；Service 只负责常驻通知与
 * 「停止」入口，因此 Activity/Flutter 引擎重建不影响已启动的本地服务。
 */
class LocalServiceService : Service() {

    companion object {
        private const val CHANNEL_ID = "edgecube_local_service"
        private const val NOTIF_ID = 1002
        private const val ACTION_START = "com.venti1112.edgecube.action.START_LOCAL_SERVICE"
        private const val ACTION_STOP = "com.venti1112.edgecube.action.STOP_LOCAL_SERVICE"

        fun start(context: Context) {
            val intent = Intent(context, LocalServiceService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocalServiceService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> LocalServiceManager.getInstance(applicationContext).stop()
            else -> startInForeground()
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        ensureChannel()
        val notification = buildNotification()
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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "本地服务运行状态",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "EdgeCube 后端在本机运行时的常驻通知"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            flags,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, LocalServiceService::class.java).apply { action = ACTION_STOP },
            flags,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("本地服务运行中")
            .setContentText("Minecraft 服务器后端正在本机运行")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .build()
    }
}
