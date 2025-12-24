allprojects {
    repositories {
        // 优先使用官方源，阿里云镜像作为备用
        google()
        mavenCentral()
        // 阿里云镜像作为备用（如果官方源失败）
        maven { 
            setUrl("https://maven.aliyun.com/repository/public")
            isAllowInsecureProtocol = false
        }
        maven { 
            setUrl("https://maven.aliyun.com/repository/google")
            isAllowInsecureProtocol = false
        }
        maven { 
            setUrl("https://maven.aliyun.com/repository/gradle-plugin")
            isAllowInsecureProtocol = false
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // 为所有子项目（Flutter 插件）设置 compileSdk
    // 这解决了 share_plus 等插件无法访问 flutter 扩展的问题
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    // 尝试作为 LibraryExtension 设置 compileSdk
                    val libraryExtension = android as? com.android.build.gradle.LibraryExtension
                    if (libraryExtension != null) {
                        libraryExtension.compileSdk = 35
                    }
                } catch (e: Exception) {
                    // 忽略错误
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
