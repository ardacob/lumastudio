# Luma Studio

Photoshop'tan esinlenen, Soft UI görünümlü yerel macOS fotoğraf düzenleyici.

## Kullanım

`outputs/Luma Studio.app` uygulamasını açın. **Yeni** ile boş tuval oluşturun veya bir görseli pencereye sürükleyip **Aç** düğmesini kullanın. **Katmanlar** bölümünden başka görseller, metin ve şekiller ekleyin. Bir katmanı seçip tuvalde **Taşı** aracını kullanın; **Fırça** ile ayrı çizim katmanları oluşturun. Katmanları sıralayın, gizleyin, çoğaltın, silin veya opaklığını değiştirin. **Katmanlı projeyi kaydet** ile çalışmayı `.luma` dosyasına kaydedin; aynı dosyayı **Aç** ile yeniden yükleyin. Yeni bir çalışmaya geçerken kaydedilmemiş düzenleme varsa uygulama uyarır.

**Düzenle** bölümünden ışık ve renk ayarlarını, hazır görünümleri, merkezden kırpma ve döndürmeyi uygulayın. **Çıktı** panelinde biçimi seçip düzleştirilmiş görseli dışa aktarın. **Ayarlar** bölümünden sistem/açık/koyu görünüm, varsayılan çıktı biçimi ve kayıplı çıktı kalitesini seçin; tercihler sonraki açılışlarda korunur.

## Teknik bilgiler

- macOS 14 veya üzeri; Apple Silicon ve Intel Mac için evrensel uygulama.
- Apple'ın sistem fontu San Francisco kullanılır.
- Görseller Core Image ile işlenir; tam çözünürlükte dışa aktarılır.
- Açılabilen biçimler kurulu macOS ImageIO/Core Image kod çözücülerine, dışa aktarma listesi ise macOS kodlayıcılarına bağlıdır. PSD dışa aktarma tek katmanlı sonuç verir.
- Görsel, metin, şekil ve fırça katmanları; katman sırası, görünürlük, opaklık, taşıma, çoğaltma, silme ve `.luma` katmanlı proje kaydı içerir.
- Hazır görünümler, 10 genel ayar, kırpma oranları, döndürme, yatay yansıtma, yakınlaştırma, geri alma ve yineleme içerir.

Maskeleme, gelişmiş seçim araçları, katman başına filtreler, Photoshop eklentileri ve Adobe PSD katman yapısının birebir içe/dışa aktarımı henüz bulunmaz. PSD çıktı düzleştirilir.

## Yeniden derleme

Xcode Command Line Tools kurulu bir Mac'te `LumaStudio/build.sh` çalıştırın. Derlenen uygulama `outputs/Luma Studio.app` konumuna yazılır.
