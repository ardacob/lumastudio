# Doğrulama kapsamı

Geliştirme sohbetlerinde örnek görsel açma/düzenleme/PNG çıktı, koyu görünüm, tercih kalıcılığı, Apple Silicon/Intel derlemeleri, `.luma` katman kaydı/yeniden açma ve birleşik görsel çıktı kontrolleri kayda geçmiştir.

Bu aktarımda kaynak ve build araçları incelenmiştir. Önceki GUI kontrolleri bu oturumda yeniden çalıştırılmış kabul edilmez. Sistem kodlayıcıları değişebileceği için her çıktı biçiminin bütün Mac'lerde doğrulandığı iddia edilmez. Katmanlı PSD ve maskeler mevcut olmadığından bunlar başarıyla test edilmiş özellikler değildir.

## 1 Ekim 2026 kaynak aktarımı kontrolü

Mac uygulaması bu depodaki betikle yeniden derlendi. İkili mimarileri: **x86_64 arm64**. Yerel ad-hoc imza `codesign --verify --deep --strict` ile doğrulandı. Bu oturumda GUI işlevleri ve mobil cihaz testi yeniden yapılmadı.
