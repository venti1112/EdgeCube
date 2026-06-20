# 归档解压相关库的 R8 keep 规则。

# commons-compress / lz4-java / junrar 引用的一些类来自可选依赖，
# R8 在 minify 时会报缺失类。补充实际依赖后通常不再需要，但保留 dontwarn
# 作为兜底，防止传递依赖版本变化导致构建失败。

# FramedLZ4CompressorInputStream 引用 commons-codec 的 XXHash32（已显式依赖）。
-dontwarn org.apache.commons.codec.digest.XXHash32

# junrar 使用 slf4j，其静态绑定实现可能被裁剪（已显式依赖 slf4j-jdk14）。
-dontwarn org.slf4j.impl.StaticLoggerBinder

# Apache FTPServer 及其依赖 mina-core 使用反射与 slf4j，保留实现类。
-dontwarn org.apache.ftpserver.**
-dontwarn org.apache.mina.**
-keep class org.apache.ftpserver.** { *; }
-keep class org.apache.mina.** { *; }

# Apache MINA SSHD（SSH/SFTP 服务器）与 BouncyCastle 大量使用反射、ServiceLoader
# 与安全 provider 注册，R8 minify 时会误删；全量保留并忽略可选依赖告警。
# 注意：上面的 org.apache.mina.** 是 FTPServer 的 mina-core，并不覆盖 org.apache.sshd。
-keep class org.apache.sshd.** { *; }
-dontwarn org.apache.sshd.**
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
# SSHD 通过 ServiceLoader 发现安全 provider 注册器与 IO 工厂，保留其实现类。
-keep class * implements org.apache.sshd.common.util.security.SecurityProviderRegistrar { *; }
-keep class * implements org.apache.sshd.common.io.IoServiceFactoryFactory { *; }
-dontwarn java.nio.file.**
