# Deskripsi Arsitektur Aplikasi SKSK

Aplikasi ini dibangun sebagai *Progressive Web App* (PWA) menggunakan Google Apps Script sebagai backend dan Google Sheets sebagai database. Antarmukanya dibuat dengan HTML dan Tailwind CSS, serta ditenagai oleh JavaScript di sisi klien untuk interaktivitas.

Berikut adalah rincian fungsi dari setiap file dalam proyek ini:

### 📄 `index`
File ini adalah kerangka utama dan titik masuk dari antarmuka pengguna (UI) aplikasi.

* **Fungsi**: Mendefinisikan struktur visual dan tata letak halaman web yang dilihat oleh pengguna.
* **Komponen Utama**:
    * **Header**: Berisi judul aplikasi dan tombol navigasi utama ("Main" dan "Setup").
    * **Tampilan (Views)**: Terdapat dua bagian utama:
        * `setupView`: Halaman untuk pengguna pertama kali, di mana mereka dapat membuat database baru dan mengelola data master.
        * `appView`: Halaman aplikasi utama untuk penggunaan sehari-hari, berisi formulir penambahan transaksi serta laporan.
    * **Styling**: Menggunakan *framework* [Tailwind CSS](https://tailwindcss.com/) untuk memberikan gaya visual pada elemen HTML.
    * **Integrasi PWA**:
        * Menghubungkan ke file `manifest` untuk fungsionalitas "Add to Home Screen".
        * Mendaftarkan `service-worker` untuk memungkinkan aplikasi berjalan secara offline.
    * **Skrip Aplikasi**: Memuat file `app` yang berisi semua logika interaktif di sisi klien.

### ⚙️ `Backend`
File ini adalah "otak" aplikasi yang berjalan di server Google. Semua logika pemrosesan data, bisnis, dan interaksi dengan database terpusat di sini.

* **Fungsi**: Bertindak sebagai *backend service* yang mengelola data dan logika aplikasi.
* **Tugas Utama**:
    * **Web Server**: Fungsi `doGet` menangani permintaan HTTP untuk menyajikan halaman `index` dan aset PWA lainnya (`manifest`, `service-worker`).
    * **Manajemen Database**: Menyediakan fungsi untuk membuat database Google Sheet baru dari *template* (`createNewDb`) dan menghubungkannya ke aplikasi.
    * **Operasi Data (CRUD)**: Berisi fungsi-fungsi untuk menambah, membaca, dan mengelola data master seperti:
        * Wallets (`createWallet`, `getWallets`).
        * Categories (`createCategory`, `getCategories`).
        * Transactions (`addTransaction`, `getTransactions`).
        * Goals (`createGoal`, `getGoalsWithProgress`).
    * **Logika Bisnis**:
        * Memvalidasi input transaksi.
        * Secara otomatis membuat transaksi kembar ("twin") untuk jenis transfer (`isTransferOut`).
        * Menghitung nilai `AdjustedAmount` (positif untuk pemasukan, negatif untuk pengeluaran).
    * **Caching**: Menggunakan `CacheService` untuk menyimpan data yang sering diakses (seperti daftar kategori dan dompet) sementara waktu, demi meningkatkan performa.

### 🎮 `app`
File ini adalah "sistem saraf" yang berjalan di browser pengguna. Ia membuat aplikasi menjadi hidup, interaktif, dan responsif terhadap input pengguna.

* **Fungsi**: Mengelola status antarmuka, menangani interaksi pengguna, dan berkomunikasi dengan `Backend`.
* **Tugas Utama**:
    * **Manajemen State**: Menyimpan data yang diambil dari *backend* (seperti daftar dompet dan kategori) dalam variabel JavaScript untuk digunakan di seluruh UI.
    * **Event Handling**: Menangani semua aksi pengguna, seperti:
        * Mengklik tombol untuk beralih antara `setupView` dan `appView`.
        * Mengisi dan mengirim formulir transaksi.
        * Memfilter riwayat transaksi melalui kolom pencarian.
    * **Komunikasi dengan Backend**: Menggunakan `google.script.run` untuk memanggil fungsi di `Backend` secara asinkron. Ini digunakan untuk mengambil data awal (`bootstrap`) dan mengirim data baru (misalnya, saat menyimpan transaksi).
    * **Pembaruan UI Dinamis**:
        * Mengisi elemen `<select>` (dropdown) dengan data dari *backend*.
        * Merender daftar riwayat transaksi.
        * Menampilkan laporan ringkasan anggaran dan progres *goals*.
        * Menampilkan atau menyembunyikan opsi "Transfer Ke" berdasarkan subkategori yang dipilih.

### 🌐 `service-worker`
File ini adalah komponen kunci yang mengubah situs web biasa menjadi *Progressive Web App* (PWA) dengan kemampuan offline.

* **Fungsi**: Memungkinkan aplikasi untuk dimuat dan diakses bahkan tanpa koneksi internet.
* **Mekanisme Kerja**:
    * **Instalasi & Caching**: Saat pertama kali dimuat, *service worker* akan menyimpan aset-aset penting yang didefinisikan dalam `urlsToCache` ke dalam *cache* browser.
    * **Intercept Request (Fetch)**: Setiap kali aplikasi mencoba mengambil sumber daya (misalnya gambar, skrip, atau data), `service-worker` akan mencegat permintaan tersebut.
    * **Offline First Strategy**: Ia akan mencoba mengambil konten dari jaringan terlebih dahulu. Jika gagal (misalnya karena tidak ada internet), ia akan mencari respons yang cocok di dalam *cache* dan menampilkannya kepada pengguna.

### 📝 `manifest`
File ini adalah file konfigurasi JSON yang berfungsi sebagai "kartu identitas" aplikasi bagi browser dan sistem operasi.

* **Fungsi**: Menyediakan metadata yang diperlukan browser untuk mengintegrasikan aplikasi web dengan sistem operasi (misalnya, untuk fitur "Install" atau "Add to Home Screen").
* **Properti Penting**:
    * `name` & `short_name`: Nama aplikasi yang akan muncul di bawah ikon.
    * `start_url`: Halaman yang akan dibuka saat pengguna meluncurkan aplikasi dari ikonnya.
    * `display`: Dikonfigurasi sebagai `standalone` agar aplikasi berjalan di jendelanya sendiri tanpa UI browser, memberikan kesan seperti aplikasi *native*.
    * `icons`: Daftar ikon dalam berbagai ukuran untuk digunakan di *home screen*, *app launcher*, dll.
    * `background_color` & `theme_color`: Menentukan warna untuk *splash screen* dan *toolbar* aplikasi.
