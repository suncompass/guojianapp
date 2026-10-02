import java.util.Properties
import java.util.Base64
import java.security.MessageDigest
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val dartDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(",").filter { it.isNotEmpty() }
    .associate {
        val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        decoded.substringBefore("=") to decoded.substringAfter("=", "")
    }
val allSources = dartDefines["ALL_SOURCES"] == "true"

val releaseKey = rootProject.file("key.properties")
val releaseProperties = Properties()
if (releaseKey.exists()) {
    releaseKey.inputStream().use { releaseProperties.load(it) }
}

android {
    namespace = "com.duanju.duanju_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.duanju.duanju_app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = if (allSources) "真果鉴" else "红果鉴"
        manifestPlaceholders["appBanner"] = if (allSources) "@drawable/tv_banner_all_sources" else "@drawable/tv_banner"
    }

    signingConfigs {
        if (releaseKey.exists()) {
            create("release") {
                storeFile = file(requireNotNull(releaseProperties.getProperty("storeFile")))
                storePassword = requireNotNull(releaseProperties.getProperty("storePassword"))
                keyAlias = requireNotNull(releaseProperties.getProperty("keyAlias"))
                keyPassword = requireNotNull(releaseProperties.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            signingConfig = signingConfigs.getByName(if (releaseKey.exists()) "release" else "debug")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/libduanju_core.so"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

val verifyNativeCore by tasks.registering {
    doLast {
        val architectures = mapOf(
            "android-arm" to ("armeabi-v7a" to "arm"),
            "android-arm64" to ("arm64-v8a" to "arm64"),
            "android-x64" to ("x86_64" to "amd64")
        )
        val targets = providers.gradleProperty("target-platform").orNull
            ?.split(",")?.map { it.trim() }?.filter { it.isNotBlank() }
            ?.takeIf { it.isNotEmpty() } ?: architectures.keys.toList()
        for (target in targets) {
            val (abi, architecture) = architectures[target]
                ?: throw GradleException("不支持的 Android 目标架构：$target")
            val library = file("src/main/jniLibs/$abi/libduanju_core.so")
            val manifest = file("src/main/jniLibs/$abi/libduanju_core.build.json")
            val command = "python3 scripts/build_android.py --abi $abi" +
                if (allSources) " --all-sources" else ""
            if (!library.isFile || !manifest.isFile) {
                throw GradleException("原生核心缺少构建记录，请运行：$command")
            }
            val metadata = JsonSlurper().parse(manifest) as? Map<*, *>
                ?: throw GradleException("原生核心构建记录无效，请运行：$command")
            if (metadata["format"] != 1 || metadata["allSources"] != allSources ||
                metadata["platform"] != "android" || metadata["architecture"] != architecture) {
                throw GradleException("应用与原生核心的站源配置不一致，请运行：$command")
            }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(library.readBytes()).joinToString("") { "%02x".format(it) }
            if (metadata["sha256"] != digest) {
                throw GradleException("原生核心已改变，请重新运行：$command")
            }
        }
    }
}

tasks.named("preBuild") { dependsOn(verifyNativeCore) }

tasks.withType<JavaCompile>().configureEach {
    if (name.contains("Release")) {
        doFirst {
            val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
            if (registrant.exists()) {
                val generated = registrant.readText()
                val integrationPlugin = Regex(
                    """(?s)    try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{[^}]*\}\s*"""
                )
                val release = generated.replace(integrationPlugin, "")
                if (release != generated) registrant.writeText(release)
            }
        }
    }
}
