"""Доводит сгенерированный `flutter create` android-проект до рабочего состояния.

В ветке chatsen1 нет папки android/ — её генерирует `flutter create`, но шаблон
не знает о нуждах Chatsen. Скрипт:
  * добавляет INTERNET (в release-манифесте шаблона его нет -> чат не грузится),
    POST_NOTIFICATIONS, WAKE_LOCK, FOREGROUND_SERVICE;
  * <queries> для открытия https-ссылок (url_launcher, Android 11+);
  * включает core library desugaring (требует flutter_local_notifications >= 10);
  * меняет подпись приложения на «Chatsen Mod».
Запуск: python3 tool/android_setup.py  (из корня проекта, после flutter create)
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / "android"
if not root.exists():
    sys.exit("android/ not found — run `flutter create` first")

# ---------- AndroidManifest.xml ----------
manifest = root / "app/src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
]
block = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
m = re.sub(r"(<manifest[^>]*>\n)", lambda x: x.group(1) + block, m, count=1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Chatsen Mod"', m, count=1)
if "android.intent.action.VIEW" not in m.split("<queries>")[-1]:
    view_query = (
        "        <intent>\n"
        '            <action android:name="android.intent.action.VIEW"/>\n'
        '            <data android:scheme="https"/>\n'
        "        </intent>\n"
    )
    if "<queries>" in m:
        m = m.replace("<queries>\n", "<queries>\n" + view_query, 1)
    else:
        m = m.replace("</manifest>", "    <queries>\n" + view_query + "    </queries>\n</manifest>")
manifest.write_text(m)

# ---------- app/build.gradle(.kts) ----------
kts = root / "app/build.gradle.kts"
groovy = root / "app/build.gradle"
if kts.exists():
    g = kts.read_text()
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"(compileOptions\s*\{\n)", r"\1        isCoreLibraryDesugaringEnabled = true\n", g, count=1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(g)
elif groovy.exists():
    g = groovy.read_text()
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"(compileOptions\s*\{\n)", r"\1        coreLibraryDesugaringEnabled true\n", g, count=1)
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g)
else:
    sys.exit("app/build.gradle(.kts) not found")

print("android/ patched OK")
