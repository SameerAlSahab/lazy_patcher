# 🚀 Lazy Framework Patcher  (PATCH APKS && JARS IN 2 MINUTES!!)

> **"Patch your Android ROM's framework, services, or any JAR/APK—remotely, reliably, and effortlessly with GitHub Actions."**

---

## 🛠️ What is Lazy Framework Patcher?

**Lazy Framework Patcher** is a highly-automated solution for remotely patching Android firmware components—including `framework.jar`, `services.jar`, custom `.jar` files, and APKs. Designed for modders, developers, and advanced users, it leverages GitHub Actions to perform patching in the cloud, with robust patch validation and artifact management.

---

## ✨ Features

- **Remote Patching:** Upload or link your JAR/APK files for instant, cloud-based patching.
- **Multi-File Support:** Patch any number of JARs or APKs in a single run.
- **Automated Patch Discovery:** Auto-applies patches from the `patches/` directory for each file.
- **Android 14+ Compatibility:** Special handling for latest Android resources.
- **Clean Artifacts:** Download your patched files in a single, organized archive.
- **Open Source & Extensible:** Just add patch files to extend or customize behavior.

---

## 📦 Usage

### 1. **Fork or Clone This Repository**

```shell
git clone https://github.com/Ishihara0Xn/lazy_patcher.git
cd lazy_patcher
```

### 2. **Add Your Patch Files**

- Place `.patch` files inside `patches/<jarname>/` or `patches/<apkname>/` directories.
- Example:
  ```
  patches/
    framework/
      my_custom_framework.patch
    services/
      my_services_patch.patch
  ```

### 3. **Run via GitHub Actions**

#### **Manual Dispatch**

1. Go to the "Actions" tab in your forked repo.
2. Select **"Lazy Framework Patcher"** workflow.
3. Click **"Run workflow"**.
4. Paste URLs for your `.jar` and/or `.apk` files, one per line:
   ```
   https://yourserver.com/path/to/framework.jar
   https://yourserver.com/path/to/services.jar
   https://yourserver.com/path/to/yourapp.apk
   ```
5. Click **"Run workflow"** again.

#### **Automated Patch via API**

You can also trigger this workflow programmatically using the [GitHub Actions API](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event).

---

## 🧑‍💻 How It Works

1. **File Download:** All provided URLs are automatically downloaded and sorted by type.
2. **Patch Application:** Each file is decompiled, validated, and patched using your provided `.patch` files.
3. **Build & Repackage:** Files are rebuilt and Android 14 resources are handled gracefully.
4. **Artifact Collection:** All patched files are zipped and made available for download.

---

## 💡 Example Patch Directory Structure

```text
patches/
  framework/
    disable_signature_check.patch
  services/
    enable_logcat.patch
  core/
    optimize_performance.patch
  myapp/
    unlock_premium.patch
```

---

## 📝 Credits

> _Developed and maintained by_  
> **Ishihara0Xn**
>
> Apktool by iBotPeaches

- [GitHub: @Ishihara0Xn](https://github.com/Ishihara0Xn)
- Script, workflow design, and patching logic by Ishihara0Xn.

---

## 🏷️ License

Licensed under the MIT License.  
See [LICENSE](./LICENSE) for details.

---

> **"Built for power users, by a power user. Patch smart, patch safe, patch anywhere."**
