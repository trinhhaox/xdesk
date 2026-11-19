package vn.xox.xdesk.update

const val SHA_A = "daf7120e854a23e9f2475081be551caa9c1f620e4950ea4d7c39436a9d8284c1"

fun manifestJson(
    versionCode: String = "2",
    versionName: String = "\"0.1.1-beta\"",
    apkUrl: String = "\"https://github.com/trinhhaox/xdesk-releases/releases/download/v0.1.1-beta/xdesk-0.1.1-beta.apk\"",
    sha256: String = "\"$SHA_A\"",
    size: String = "1234",
    minSdk: String = "31",
    releaseNotes: String = "\"Sửa lỗi\"",
    publishedAt: String = "\"2026-11-20T01:00:00Z\"",
): String = """{"versionCode":$versionCode,"versionName":$versionName,"apkUrl":$apkUrl,"sha256":$sha256,"size":$size,"minSdk":$minSdk,"releaseNotes":$releaseNotes,"publishedAt":$publishedAt}"""

fun manifestOf(versionCode: Long = 2, minSdk: Int = 31) =
    UpdateManifest(versionCode, "0.1.1-beta", "https://example.test/x.apk", SHA_A, 1234, minSdk, "", "2026-11-20T01:00:00Z")

class MemoryStore(override var lastCheckMs: Long? = null) : LastCheckStore
