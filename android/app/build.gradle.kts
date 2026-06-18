import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 서명 설정 로드 — android/key.properties (gitignore됨, 비밀). 키 자체는
// repo 밖(~/)에 두고 storeFile 절대경로로 참조. 파일 없으면 debug 서명 fallback
// (기여자/CI가 키 없이도 빌드됨, 단 그 산출물은 Play 업로드 불가).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.synchorus.synchorus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.synchorus.synchorus"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        prefab = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties 있으면 release 키로 서명, 없으면 debug fallback.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 코드 축소/난독화 OFF. 켜져 있으면(AGP/Flutter 기본) audio_service의
            // MediaStyle 알림용 androidx.media 클래스가 release에서 제거돼 미디어 알림이
            // 기본 FGS 알림("실행 중")으로 깨졌음 — MediaSession(매니페스트 등록 클래스라
            // 유지)만 살아있고 미니플레이어/잠금화면 컨트롤이 안 떴다. debug(R8 미적용)는 정상.
            // 네이티브 스택(oboe/nsd/ffi/audio_service) 많아 keep 규칙 누락 위험 커 v1은
            // minify를 끄는 게 안전. 크기 최적화 필요 시 추후 keep 규칙 추가 후 재검증.
            // (2026-06-18 실측: minify ON일 때만 미디어 알림 깨짐 확인.)
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    // oboe 1.9.0 prebuilt AAR의 liboboe.so는 LOAD align 0x1000(4KB)으로 16KB
    // 미정렬이었음(실측 확인, 2026-06-01). Android 16KB page size 대응 위해 1.9.3로
    // 상향 — 빌드 후 liboboe.so align 0x4000 재실측으로 검증할 것.
    implementation("com.google.oboe:oboe:1.9.3")
}

flutter {
    source = "../.."
}
