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
    project.evaluationDependsOn(":app")
}

// Work around stale flutter_avif_android (Java 11, defaulted Kotlin 21,
// duplicate FlutterAvifPlugin stub in java/ + kotlin/): KGP >= 2.1 rejects
// the JVM-target mix, current toolchains reject the stub pair
// (Redeclaration), and only JDK 17 is installed.
// Decoding runs via FFI against the bundled libflutter_avif.so, so the
// stubs are irrelevant: align javac to 17 and skip kotlinc for this module,
// compiling the stub from the Java source instead.
gradle.afterProject {
    if (project.name != "flutter_avif_android" && project.name != "onnxruntime") {
        return@afterProject
    }
    // New AGP 9 DSL type (com.android.build.gradle.LibraryExtension was
    // removed). Setting compileOptions here propagates to the javac task.
    extensions
        .findByType<com.android.build.api.dsl.LibraryExtension>()
        ?.let {
            // Stale plugin compileSdkVersions predate their androidx deps
            // (need 34+): flutter_avif_android=31, onnxruntime=33.
            it.compileSdk = 36
            it.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            it.compileOptions.targetCompatibility = JavaVersion.VERSION_17
        }
    if (project.name != "flutter_avif_android") return@afterProject
    tasks
        .withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
        .configureEach {
            enabled = false
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
