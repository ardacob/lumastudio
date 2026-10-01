# LumaStudio

<p align="center"><img src="LumaStudio/AppIcon-1024.png" alt="LumaStudio simgesi" width="140"></p>

**macOS için katmanlı görsel düzenleme uygulaması.** Arda Çobanoğlu tarafından Codex ile geliştirilir. Photoshop'un katmanlı çalışma mantığından esinlenir; Soft UI ve macOS sistem fontunu kullanır.

## Platform ve durum

- **macOS 14+**, Apple Silicon ve Intel için evrensel uygulama.
- Mevcut uygulama metadata'sı: **1.3 / Build 4**.
- Yerel SwiftUI/AppKit arayüzü; Core Image işleme, ImageIO dışa aktarma.
- Kaynaklar mevcut geliştirme çalışmasından aktarılmıştır; geçmiş sohbet aşamaları için yapay Git commit'leri veya sürüm etiketleri oluşturulmamıştır.

## Katmanlı çalışma

- **Yeni** ile boş tuval oluşturma veya görsel açma/sürükleyip bırakma.
- Görsel, metin, dikdörtgen, elips ve fırça katmanları.
- Seçili katmanı tuvalde taşıma.
- Katman sıralama, görünürlük, opaklık, çoğaltma ve silme.
- Ayrı fırça katmanında çizim.
- Düzenlenebilir çalışmayı **`.luma`** olarak kaydetme ve yeniden açma.
- Kaydedilmemiş düzenleme varken yeni çalışmaya geçiş uyarısı.

## Görsel düzenleme

10 ışık/renk/detay ayarı: **pozlama, parlaklık, kontrast, açık alanlar, gölgeler, doygunluk, canlılık, sıcaklık, keskinlik ve vinyet**.

Hazır görünümler, özgün / 1:1 / 4:3 / 3:2 / 16:9 / 4:5 kırpma oranları, döndürme, yatay yansıtma, yakınlaştırma, geri alma ve yineleme de bulunur. Mevcut ayarlar katman başına filtre sistemi değildir.

## Görünüm ve ayarlar

**Sistem, Açık ve Koyu** görünüm; varsayılan çıktı biçimi ve kayıplı biçim kalite tercihi Ayarlar bölümündedir. Tercihler sonraki açılışlarda korunur.

## Biçim desteği

Açılabilen dosyalar kurulu macOS ImageIO/Core Image kod çözücülerine, çıktı listesi sistem kodlayıcılarına bağlıdır. Geliştirme ortamında PNG, JPEG, HEIC, TIFF, BMP, GIF, AVIF ve PSD çıktı seçenekleri listelenmiştir; bu liste bütün Mac'lerde aynı destek garantisi değildir.

**PSD çıktısı düzleştirilmiş, tek katmanlı görseldir.** Düzenlenebilir LumaStudio katmanlarını korumak için `.luma` kullanın. Maskeleme, gelişmiş seçimler, katman başına filtreler, Photoshop eklentileri ve katmanlı Adobe PSD içe/dışa aktarımı mevcut değildir.

## Kullanım

1. **Yeni** ile tuval oluşturun veya **Aç** ile görsel seçin.
2. **Katmanlar** panelinden görsel, yazı, şekil veya fırça ekleyin.
3. Katmanı seçip **Taşı** ile konumlandırın; sırasını ve opaklığını ayarlayın.
4. **Düzenle**, **Stiller** ve **Kırp** panellerinden görseli düzenleyin.
5. Katmanları korumak için `.luma` kaydedin; paylaşılacak birleşik görsel için **Çıktı** kullanın.

| İşlem | Kısayol |
| --- | --- |
| Yeni | ⌘N |
| Aç | ⌘O |
| Proje kaydet | ⌘S |
| Farklı kaydet | ⇧⌘S |
| Geri al / yinele | ⌘Z / ⇧⌘Z |

## Derleme

Xcode Command Line Tools, Python 3 ve macOS'un `sips`, `lipo`, `codesign` araçları gerekir. Simge oluşturma betikleri üçüncü taraf Python kütüphanesi gerektirmez.

```sh
zsh LumaStudio/build.sh
open "outputs/Luma Studio.app"
```

Betik arm64 ve x86_64 ikililerini birleştirir ve yerel ad-hoc imza uygular. Apple Developer dağıtım imzası/notarization yapmaz.

## Depo yapısı

- `LumaStudio/Sources/LumaStudio.swift`: arayüz, belge/katman modeli, görüntü işleme ve çıktı.
- `LumaStudio/Info.plist`: uygulama ve `.luma` belge metadata'sı.
- `LumaStudio/build.sh`: evrensel uygulama derlemesi.
- `LumaStudio/create_icon.py`, `create_icns.py`: simge araçları.
- `docs/`: gelişim geçmişi, ilk kaynak README'si ve doğrulama kapsamı.

[Geliştirme geçmişi](docs/DEVELOPMENT-HISTORY.md) · [Doğrulama kaydı](docs/VALIDATION.md)

## Lisans

Bu aktarımda açık kaynak lisansı seçilmemiştir. Photoshop'tan esinlenme, Adobe uyumluluğu veya Adobe ile bağlantı iddiası değildir.
