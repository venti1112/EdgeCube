package com.venti1112.edgecube

import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import com.venti1112.edgecube.channels.ArchiveChannel
import com.venti1112.edgecube.channels.EcpkgChannel
import com.venti1112.edgecube.channels.ForgeChannel
import com.venti1112.edgecube.channels.FtpChannel
import com.venti1112.edgecube.channels.PermissionChannel
import com.venti1112.edgecube.channels.PermissionsController
import com.venti1112.edgecube.channels.PhotoChannel
import com.venti1112.edgecube.channels.PowerChannel
import com.venti1112.edgecube.channels.ProotChannel
import com.venti1112.edgecube.channels.RuntimeChannel
import com.venti1112.edgecube.channels.ServerChannel
import com.venti1112.edgecube.channels.ShellChannel
import com.venti1112.edgecube.channels.SshChannel
import com.venti1112.edgecube.channels.StorageChannel
import com.venti1112.edgecube.channels.SystemMonitorChannel
import com.venti1112.edgecube.channels.TunnelChannel
import com.venti1112.edgecube.channels.UpdateChannel
import com.venti1112.edgecube.keepalive.KeepAliveManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 平台通道宿主。
 *
 * 各通道的注册与实现按领域拆分在 [com.venti1112.edgecube.channels] 包中
 * （一个通道一个文件），此处只负责 Activity 生命周期、权限回调分发与
 * `.ecpkg` 打开 intent 的转发。
 */
class MainActivity : FlutterActivity() {

    /** 运行时权限申请与 onRequestPermissionsResult 回调的暂存/兑现。 */
    private val permissions = PermissionsController(this)

    /** `.ecpkg` 文件关联入口（engine 就绪前暂存路径，就绪后补发）。 */
    private val ecpkgChannel = EcpkgChannel(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ecpkgChannel.handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // 绑定当前 Activity 供防息屏使用：服务端运行且开启防息屏时，
        // 由 KeepAliveManager 在窗口上添加 FLAG_KEEP_SCREEN_ON。
        // 转屏/重建后 Activity 重建，onResume 重新绑定并补上标志。
        KeepAliveManager.bindActivity(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        ecpkgChannel.handleIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        this.permissions.onRequestPermissionsResult(requestCode)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val appContext = applicationContext

        ecpkgChannel.attach(messenger)

        // —— 需要 Activity 的通道（权限申请、页面跳转、返回键策略）——
        PermissionChannel.register(messenger, permissions)
        StorageChannel.register(messenger, this, permissions)
        PhotoChannel.register(messenger, this, permissions)
        PowerChannel.register(messenger, this)

        // —— 仅需 Context 的通道 ——
        ServerChannel.register(messenger, appContext)
        SystemMonitorChannel.register(messenger, appContext)
        ForgeChannel.register(messenger, appContext)
        ArchiveChannel.register(messenger)
        FtpChannel.register(messenger)
        SshChannel.register(messenger, appContext)
        UpdateChannel.register(messenger, appContext)
        ShellChannel.register(messenger, appContext)
        TunnelChannel.register(messenger, appContext)
        RuntimeChannel.register(messenger, appContext)
        ProotChannel.register(messenger, appContext)
    }
}
