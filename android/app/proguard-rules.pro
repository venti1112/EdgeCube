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
