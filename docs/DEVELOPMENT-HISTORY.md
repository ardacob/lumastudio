# Geliştirme geçmişi

Kaynak: “MacOS Photoshop benzeri uygulama yap” sohbeti ve eldeki kaynak/teslim dosyaları. Bu kayıtlar geliştirme aşamalarıdır; yayımlanmış GitHub release geçmişi değildir.

1. **İlk talep:** macOS uygulaması, Photoshop referansı, Neomorphism/Soft UI ve Apple sistem fontu; geniş görsel biçim desteği.
2. **İlk çalışan düzenleyici:** Görsel açma/sürükleme, 10 ışık ve renk ayarı, hazır stiller, kırpma, döndürme/yansıtma, geri alma ve çıktı. Örnek görselle aç–düzenle–PNG aktar akışı kayda geçti. Bu ilk aşamada katman/fırça yoktu.
3. **Tema ve ayarlar:** Sistem/Açık/Koyu görünüm, varsayılan çıktı biçimi ve kalite tercihleri eklendi. Koyu görünüm ve yeniden açmada tercihlerin kalıcılığı kontrol edildi. Apple Silicon/Intel evrensel derleme hazırlandı.
4. **Katmanlı çalışma:** Boş tuval, görsel/metin/şekil/fırça katmanları, taşıma, sıralama, gizleme, çoğaltma, silme ve opaklık geliştirildi. `.luma` belge kaydı ve yeniden açma eklendi.
5. **Belge/çıktı kontrolü:** Katmanları kaydedip yeniden açma ve birleşik görsel çıktısı doğrulandı. Güncel kaynak metadata'sı 1.3 / Build 4'tür.

Önceki “katman yok” açıklaması ilk sürüme aittir; güncel kaynak katmanları içerir. Katmanlı PSD, maske ve gelişmiş seçim desteği ise hâlâ yoktur.
