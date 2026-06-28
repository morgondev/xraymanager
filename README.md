# Xray Manager

**Custom Xray-core builder & installer with PR #5844 (UserConnTracker)**

Xray Manager یک ابزار مدیریتی برای بیلد و نصب نسخه کاستوم Xray-core هست که مشکل مصرف اضافه‌تر (Extra Connection) رو حل می‌کنه. این اسکریپت هسته Xray رو از سورس با پچ [UserConnTracker](https://github.com/XTLS/Xray-core/pull/5844) بیلد می‌کنه و روی پنل مورد نظر نصب می‌کنه.

---

## پنل‌های پشتیبانی شده

| پنل | نوع استقرار | وضعیت |
|---|---|---|
| **PasarGuard Node** | Docker | ✅ |
| **3X-UI (Sanaei)** | Systemd | ✅ |
| **Marzban** | Docker | ✅ |
| **Marzneshin** | Docker (marznode) | ✅ |

---

## امکانات

- شناسایی خودکار پنل‌های نصب شده روی سرور
- بیلد Xray-core از سورس با پچ UserConnTracker
- نصب خودکار Go در صورت نیاز
- بکاپ‌گیری خودکار قبل از هر تغییر
- رول‌بک به نسخه قبلی با یک کلیک
- نمایش وضعیت سرویس، نسخه Xray، لاگ‌ها و مصرف منابع
- پشتیبانی از معماری‌های `amd64`، `arm64` و `arm`

---

## نصب سریع

```bash
bash <(curl -sL https://raw.githubusercontent.com/morgondev/xraymanager/main/xraymanager.sh)
```

یا دانلود دستی:

```bash
curl -sL https://raw.githubusercontent.com/morgondev/xraymanager/main/xraymanager.sh -o xraymanager.sh
chmod +x xraymanager.sh
sudo ./xraymanager.sh
```

---

## منوی اصلی

```
============================================================
    Xray PR Build Manager (PR #5844 - UserConnTracker)
    Supports: PasarGuard | 3X-UI | Marzban | Marzneshin
    By - Meysam
    Telegram Channel: @morgondev
============================================================

Detected panels:
  o PasarGuard Node
  x 3X-UI
  o Marzban
  x Marzneshin

Main Menu:

  1) Install Xray with PR #5844 (UserConnTracker)
  2) Rollback to default Xray
  3) Show service status
  0) Exit
```

---

## گزینه‌ها

### 1) Install - نصب هسته کاستوم

- بکاپ خودکار از وضعیت فعلی
- نصب Go (در صورت نیاز)
- کلون و بیلد Xray از برنچ UserConnTracker
- جایگزینی باینری و ری‌استارت سرویس

### 2) Rollback - بازگشت به نسخه قبلی

- بازیابی از آخرین بکاپ
- حذف باینری کاستوم
- ری‌استارت سرویس

### 3) Status - وضعیت سرویس

- وضعیت کانتینر / سرویس
- نسخه فعلی Xray و تشخیص فعال بودن پچ
- مصرف منابع (CPU / RAM)
- آخرین لاگ‌ها و بررسی خطاهای بحرانی
- لیست بکاپ‌ها

---

## مسیرهای مهم

### PasarGuard Node
| مسیر | توضیح |
|---|---|
| `/opt/pg-node/docker-compose.yml` | فایل Compose |
| `/opt/pasarguard-xray/xray` | باینری کاستوم |
| `/opt/pg-node-backups/` | بکاپ‌ها |

### 3X-UI
| مسیر | توضیح |
|---|---|
| `/usr/local/x-ui/bin/` | دایرکتوری باینری Xray |
| `/opt/x-ui-backups/` | بکاپ‌ها |

### Marzban
| مسیر | توضیح |
|---|---|
| `/opt/marzban/docker-compose.yml` | فایل Compose |
| `/opt/marzban/.env` | تنظیمات محیطی |
| `/var/lib/marzban/xray-core/xray` | باینری کاستوم |
| `/opt/marzban-backups/` | بکاپ‌ها |

### Marzneshin
| مسیر | توضیح |
|---|---|
| `/etc/opt/marzneshin/docker-compose.yml` | فایل Compose |
| `/var/lib/marznode/xray` | باینری کاستوم |
| `/opt/marzneshin-backups/` | بکاپ‌ها |

---

## پیش‌نیازها

- سیستم‌عامل **Linux** (Ubuntu / Debian / CentOS)
- دسترسی **root**
- **Docker** و **Docker Compose** (برای پنل‌های داکری)
- **git** و **wget**
- اتصال اینترنت (برای دانلود Go و کلون ریپو)

> Go به صورت خودکار نصب می‌شه اگه روی سرور نباشه.

---

## نحوه عملکرد

1. اسکریپت پنل‌های نصب شده روی سرور رو شناسایی می‌کنه
2. Go رو نصب یا آپدیت می‌کنه
3. سورس Xray-core رو از برنچ `UserConnTracker` کلون و بیلد می‌کنه
4. بسته به نوع پنل:
   - **PasarGuard**: باینری رو به صورت volume mount به کانتینر اضافه می‌کنه
   - **3X-UI**: باینری Xray رو مستقیم جایگزین می‌کنه
   - **Marzban**: باینری رو در مسیر دیتا قرار می‌ده و `XRAY_EXECUTABLE_PATH` رو در `.env` تنظیم می‌کنه
   - **Marzneshin**: باینری رو در مسیر marznode قرار می‌ده و `XRAY_EXECUTABLE_PATH` رو در compose آپدیت می‌کنه

---

## لایسنس

MIT License

---

## ارتباط

- **GitHub**: [github.com/morgondev/xraymanager](https://github.com/morgondev/xraymanager)
- **Telegram**: [@morgondev](https://t.me/morgondev)

---

**By Meysam**
