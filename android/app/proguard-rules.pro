# ---------------------------------------------------------------------------
# R8 / JNI 反射保护
#
# Flutter 3.44 起 release 构建默认开启 R8（FlutterPlugin.kt：
# releaseBuildType.isMinifyEnabled = true，可用 gradle 属性 shrink=false 关闭）。
#
# shared_preferences_android 2.5.0 改用 Pigeon JNI：Dart 侧通过 JNI
# GetMethodID 按「原始 JVM 签名」查找 Kotlin 方法，而 Kotlin 的 suspend 函数
# 在字节码里是：
#     getAll(String, List, kotlin.coroutines.Continuation) -> Object
# R8 会把 kotlin.coroutines.Continuation 这类纯签名类型重命名（实测 -> J3.d），
# 于是运行时抛：
#     NoSuchMethodError: no non-static method
#       "Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;.getAll(
#          Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
#
# 结论：凡是被 JNI 按名字查找的类型/成员，都必须保留原名字。
# 下面用 -keepnames（只保名字、仍允许裁剪）而非 -keep，尽量少牺牲体积。
# ---------------------------------------------------------------------------

# Pigeon 生成的 JNI 代理类：类名、方法名、参数类型名都要原样保留
-keepnames class io.flutter.plugins.** { *; }
-keepnames class dev.flutter.pigeon.** { *; }

# Kotlin 运行时类型必须保留原名。
# 除了 suspend 签名里的 kotlin.coroutines.Continuation，JNI 生成代码还会直接
# Class.forName / findClass 查找 kotlin.Result、kotlin.Unit 等（Pigeon ProxyApi
# 的异步返回值就包在 kotlin.Result 里）。它们被 R8 重命名后同样会抛
#   ClassNotFoundException: Didn't find class "kotlin/Result"
# 实测：kotlin.Result -> E3.e（一次修复后新冒出来的第二个错）。
-keepnames class kotlin.** { *; }
