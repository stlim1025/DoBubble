allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory.set(file("${rootProject.projectDir}/../build"))

subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.map { it.dir(project.name) })
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean") {
    doLast {
        project.delete(rootProject.layout.buildDirectory)
    }
}
