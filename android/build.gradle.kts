allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }

    tasks.withType<AbstractCopyTask>().configureEach {
        exclude("**/._*")
        exclude("**/._**")
    }

    tasks.configureEach {
        doFirst {
            try {
                val buildDir = project.layout.buildDirectory.asFile.get()
                if (buildDir.exists()) {
                    buildDir.walkBottomUp().forEach { file ->
                        if (file.name.startsWith("._")) {
                            file.delete()
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore if build directory provider is not yet available
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    if (project.name == "app") {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    } else {
        val tmpDir = System.getProperty("java.io.tmpdir")
        project.layout.buildDirectory.set(file("$tmpDir/vibe_flow_build/${project.name}"))
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.application") {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        android?.ndkVersion = "28.2.13676358"
    }
    plugins.withId("com.android.library") {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        android?.ndkVersion = "28.2.13676358"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
