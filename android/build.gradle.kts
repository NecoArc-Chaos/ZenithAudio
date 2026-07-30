allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        val ext = extensions.findByName("android")
        if (ext is com.android.build.api.dsl.CommonExtension) {
            ext.compileSdk = 36
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:2.3.20")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.3.20")
        force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.3.20")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
