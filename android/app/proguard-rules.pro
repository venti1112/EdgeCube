-dontwarn org.apache.commons.codec.digest.XXHash32
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.apache.ftpserver.**
-dontwarn org.apache.mina.**
-keep class org.apache.ftpserver.** { *; }
-keep class org.apache.mina.** { *; }
-keep class org.apache.sshd.** { *; }
-dontwarn org.apache.sshd.**
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
-keep class * implements org.apache.sshd.common.util.security.SecurityProviderRegistrar { *; }
-keep class * implements org.apache.sshd.common.io.IoServiceFactoryFactory { *; }
-dontwarn java.nio.file.**

# 保护 PTY JNI 类（native 方法通过 JNI 名查找，不可被 R8 重命名或移除）
-keep class com.venti1112.edgecube.server.EcPty { *; }

# 保护 FileDescriptor.descriptor 字段（fdFromInt 通过反射写入此字段来包装 PTY master fd）
-keepclassmembers class java.io.FileDescriptor {
    int descriptor;
}
