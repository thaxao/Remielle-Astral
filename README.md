# Remielle Astral

<p align="center">
  <b>ตัวเปิดเกมและระบบจัดการเซิร์ฟเวอร์ Zenless Zone Zero</b><br>
  รองรับทั้ง Linux (GTK 3 + WebKitGTK 4.1 / Wayland & X11) และ Windows 10/11 (WebView2)
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v1.1.5.b3.3.2--alpha-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20Windows-green.svg" alt="Platform">
  <img src="https://img.shields.io/badge/license-Apache--2.0-orange.svg" alt="License">
</p>

---

## ⚡ ติดตั้งด้วยคำสั่งเดียว (Quick Install)

คุณสามารถติดตั้ง Remielle Astral ได้ทันทีผ่าน Terminal หรือ PowerShell โดยไม่ต้องคอมไพล์เอง:

### 🐧 Linux (Bash - ทุกดิสโทร)
```bash
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.sh | bash
```
> *สคริปต์จะดาวน์โหลดตัวโปรแกรม, สร้าง Symlink ที่ `~/.local/bin/remielle-astral`, และสร้างไอคอนในเมนูโปรแกรม (Application Menu) ให้อัตโนมัติ*

### 🏹 Arch Linux (PKGBUILD / Pacman)
สำหรับผู้ใช้ Arch Linux ที่ต้องการติดตั้งเป็นระบบแพ็กเกจ:
```bash
git clone https://github.com/thaxao/Remielle-Astral.git
cd Remielle-Astral/packaging/aur/remielle-astral-bin
makepkg -si
```

### 🪟 Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.ps1 | iex
```
> *สคริปต์จะติดตั้งไปที่ `%LOCALAPPDATA%\Remielle-Astral`, สร้างทางลัดบน Desktop และ Start Menu, พร้อมเพิ่มลงใน System PATH ให้อัตโนมัติ*

### 💻 Windows (Command Prompt / CMD)
```cmd
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.cmd -o install.cmd && install.cmd && del install.cmd
```

---

## 🗑️ วิธีถอนการติดตั้ง (Uninstall)

สคริปต์ถอนการติดตั้งจะลบเฉพาะไฟล์ของลันเชอร์อย่างปลอดภัย และมีเมนูถามก่อนว่าต้องการลบการตั้งค่า (Settings/Config) ด้วยหรือไม่:

* **Linux (ติดตั้งด้วย curl)**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.sh | bash
  ```
* **Arch Linux (ติดตั้งด้วย makepkg)**:
  ```bash
  yay -R remielle-astral-bin   # หรือ sudo pacman -R remielle-astral-bin
  ```
* **Windows (PowerShell)**:
  ```powershell
  irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.ps1 | iex
  ```

---

## 🎮 วิธีติดตั้งและใช้งาน Client Patch (`Pryce.exe` + `Armorer.dll`)

ลันเชอร์เวอร์ชันนี้มาพร้อมกับ Client Patch ล่าสุด (Custom 0.2.x) ที่รองรับการอ่าน `offsets.zon` และระบบ `custom.uid`

### 1. การติดตั้งลงในตัวเกม
* **ผ่านลันเชอร์โดยตรง**: ไปที่แท็บ **Updates** หรือ **Settings** แล้วกดปุ่ม **"ติดตั้งแพตช์ Custom (Pryce.exe + Armorer.dll)"** ลันเชอร์จะสำรองไฟล์เดิมเป็น `.remielle-bak` และคัดลอกแพตช์ลงโฟลเดอร์เกมให้อัตโนมัติ
* **หรือติดตั้งด้วยตนเอง**: คัดลอกไฟล์ `Pryce.exe` และ `Armorer.dll` ในโฟลเดอร์ `patch/` ไปวางไว้ในโฟลเดอร์เดียวกับ `ZenlessZoneZeroBeta.exe`

### 2. การเปิดเกม
* **Windows**: คลิกขวาที่ `Pryce.exe` แล้วเลือก **Run as administrator (เรียกใช้ในฐานะผู้ดูแลระบบ)**
* **Linux**: เปิดผ่าน Terminal ด้วยคำสั่ง `wine Pryce.exe` (หรือกด Start ผ่าน Remielle Astral)

---

## 🎨 การปรับแต่งข้อความและสีบนหน้าจอ (`custom.uid`)

เมื่อเปิดเกมผ่าน `Pryce.exe` จะมีไฟล์ `custom.uid` อยู่ข้างไฟล์เกม คุณสามารถแก้ไขข้อความและสีได้ระหว่างเล่นเกม โดยไม่ต้องปิดเกม:

```xml
# รูปแบบการใส่สี: <color=#RRGGBB>ข้อความ</color>
<color=#00E5FF>ThaXao - Remielle Astral</color>
```
* **ตัวอย่างโค้ดสี**:
  - แดง: `#FF5555`
  - เขียว: `#50FA7B`
  - ฟ้า: `#00E5FF`
  - เหลืองทอง: `#FFD700`
  - ม่วง: `#BD93F9`
* **การอัปเดต**: หลังบันทึกไฟล์ ให้กดสลับเปลี่ยนภาษาในเกม 1 ครั้ง ข้อความบนหน้าจอจะเปลี่ยนทันที

---

## ✨ คุณสมบัติเด่นของ Remielle Astral

1. **Native Frameless Window**: ไม่มีเบื้องหลังรันค้าง ไม่ต้องเปิดเว็บพอร์ต หน้าต่างโปรแกรมทำงานแบบเนทีฟทั้งบน Linux และ Windows
2. **ระบบ Real-time ควบคุมเกม**: ปรับเปลี่ยนอุปกรณ์, จัดทีมล่วงหน้า, ปรับแต่ง HUD Text ได้แบบทันที
3. **ระบบจัดการบัญชีหลายไอดี (Multi-Account)**: แสดงรายการ UID, บัญชีผู้ใช้, สามารถรีเซ็ตรหัสผ่านหรือสร้างไอดีใหม่ได้จากลันเชอร์
4. **Bangboo Catalog & Squad Integration**: เลือกและแสดงผล Bangboo พร้อมรูปภาพอย่างสวยงาม
5. **Offsets Auto-Sync**: ดึงและตรวจสอบ offsets ตรงกับเวอร์ชันเกมอัตโนมัติ

---

## 📋 ข้อกำหนดของระบบ (System Requirements)

* **Linux**:
  - GTK 3 และ WebKitGTK 4.1 (`webkit2gtk-4.1`)
  - Wine (สำหรับรันตัวเกม Windows)
  - `curl`, `unzip`
* **Windows**:
  - Windows 10 (เวอร์ชัน 1803 ขึ้นไป) หรือ Windows 11
  - Microsoft Edge WebView2 Runtime (มีติดตั้งมากับ Windows 10/11 อยู่แล้ว)

---

## 📄 ใบอนุญาต (License)

Remielle Astral ได้รับอนุญาตให้ใช้งานภายใต้เงื่อนไข [Apache License 2.0](LICENSE)
