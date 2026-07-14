plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
}

group = "com.groundeffectsoftware.com"
version = "1.0.0"

android {
    namespace = "com.groundeffectsoftware.com.emaysleepo2"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test:2.1.0")
}

publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.groundeffectsoftware.com"
            artifactId = "emay-sleepo2"
            version = project.version.toString()

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("EMAY SleepO2 BLE SDK")
                description.set("Android BLE client and CSV parser for the EMAY SleepO2 pulse oximeter")
                url.set("https://github.com/chenders/emay-sleepo2")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://opensource.org/licenses/MIT")
                    }
                }
                developers {
                    developer {
                        name.set("AnxietyWatch")
                    }
                }
                scm {
                    connection.set("scm:git:git://github.com/chenders/emay-sleepo2.git")
                    developerConnection.set("scm:git:ssh://github.com/chenders/emay-sleepo2.git")
                    url.set("https://github.com/chenders/emay-sleepo2")
                }
            }
        }
    }
    repositories {
        maven {
            name = "sonatype"
            url = uri(
                if ((version as String).endsWith("-SNAPSHOT"))
                    "https://s01.oss.sonatype.org/content/repositories/snapshots/"
                else
                    "https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/"
            )
            credentials {
                username = findProperty("ossrh.username") as String? ?: ""
                password = findProperty("ossrh.password") as String? ?: ""
            }
        }
    }
}

signing {
    useGpgCmd()
    sign(publishing.publications["release"])
}
