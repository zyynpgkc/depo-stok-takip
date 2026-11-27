-- =====================================================================
-- Adım 4: Örnek (sentetik) veri
-- ÖNCE Authentication > Users'tan şu 3 kullanıcıyı oluşturun:
--   sorumlu@example.com, personel1@example.com, personel2@example.com
-- =====================================================================

-- 1) Kullanıcı adları ve roller
update public.profiles p set full_name = 'Ayşe Yılmaz', role = 'sorumlu'
  from auth.users u where u.id = p.id and u.email = 'sorumlu@example.com';
update public.profiles p set full_name = 'Ali Demir', role = 'personel'
  from auth.users u where u.id = p.id and u.email = 'personel1@example.com';
update public.profiles p set full_name = 'Veli Kaya', role = 'personel'
  from auth.users u where u.id = p.id and u.email = 'personel2@example.com';

-- 2) Depolar
insert into public.warehouses (code, name) values
  ('MRK', 'Merkez Depo'),
  ('SBE', 'Şube Depo');

-- 3) Raflar
insert into public.locations (warehouse_id, code)
select w.id, x.code
from (values ('MRK', 'A-01'), ('MRK', 'A-02'), ('MRK', 'B-01'),
             ('SBE', 'S-01'), ('SBE', 'S-02')) as x(wh, code)
join public.warehouses w on w.code = x.wh;

-- 4) Kim hangi depoda çalışır (sorumlu her yeri zaten görür)
insert into public.user_warehouses (user_id, warehouse_id)
select u.id, w.id
from (values ('personel1@example.com', 'MRK'),
             ('personel2@example.com', 'SBE')) as x(email, wh)
join auth.users u on u.email = x.email
join public.warehouses w on w.code = x.wh;

-- 5) Ürünler
insert into public.products (code, name, unit, critical_level) values
  ('VD-M6',   'Vida M6x20',              'adet', 200),
  ('VD-M8',   'Vida M8x30',              'adet', 150),
  ('SM-M6',   'Somun M6',                'adet', 200),
  ('RL-6204', 'Rulman 6204',             'adet', 20),
  ('KB-25',   'Elektrik kablosu 2.5mm',  'kg',   15),
  ('BY-BYZ',  'Endüstriyel boya beyaz',  'kg',   25),
  ('BY-SYH',  'Endüstriyel boya siyah',  'kg',   25),
  ('YG-10W',  'Makine yağı 10W',         'kg',   30),
  ('EL-NIT',  'Nitril eldiven',          'koli', 5),
  ('BT-KOL',  'Koli bandı',              'koli', 4),
  ('SF-STR',  'Streç film',              'koli', 3),
  ('KT-50',   'Karton kutu 50x40',       'adet', 100),
  ('PL-EUR',  'Euro palet',              'adet', 10),
  ('FL-HAV',  'Hava filtresi',           'adet', 8),
  ('KY-V40',  'V kayışı A40',            'adet', 6),
  ('SG-6A',   'Sigorta 6A',              'adet', 50),
  ('MS-YAG',  'Silikon sprey',           'adet', 12),
  ('ET-BRK',  'Barkod etiketi rulo',     'koli', 2);

-- 6) Başlangıç stokları (bazıları bilerek kritik seviyenin altında)
insert into public.stock (product_id, location_id, quantity)
select p.id, l.id, x.qty
from (values
  ('VD-M6',   'MRK', 'A-01', 850),  ('VD-M6',   'SBE', 'S-01', 120),
  ('VD-M8',   'MRK', 'A-01', 400),
  ('SM-M6',   'MRK', 'A-01', 900),  ('SM-M6',   'SBE', 'S-01', 150),
  ('RL-6204', 'MRK', 'A-02', 12),
  ('KB-25',   'MRK', 'B-01', 48.5),
  ('BY-BYZ',  'MRK', 'B-01', 60),   ('BY-BYZ',  'SBE', 'S-02', 15),
  ('BY-SYH',  'MRK', 'B-01', 18),
  ('YG-10W',  'MRK', 'B-01', 75),
  ('EL-NIT',  'MRK', 'A-02', 14),   ('EL-NIT',  'SBE', 'S-02', 6),
  ('BT-KOL',  'MRK', 'A-02', 9),
  ('SF-STR',  'SBE', 'S-02', 2),
  ('KT-50',   'MRK', 'A-02', 320),
  ('PL-EUR',  'MRK', 'B-01', 24),   ('PL-EUR',  'SBE', 'S-02', 8),
  ('FL-HAV',  'MRK', 'A-02', 5),
  ('KY-V40',  'MRK', 'A-02', 15),
  ('SG-6A',   'MRK', 'A-01', 140),
  ('MS-YAG',  'SBE', 'S-01', 30),
  ('ET-BRK',  'MRK', 'A-02', 7)
) as x(code, wh, raf, qty)
join public.products   p on p.code = x.code
join public.warehouses w on w.code = x.wh
join public.locations  l on l.warehouse_id = w.id and l.code = x.raf;

-- 7) Açılış stoklarını hareket geçmişine de yaz (geçmiş ile stok tutarlı olsun)
insert into public.stock_movements
  (request_id, type, product_id, to_location_id, quantity, user_id, note, created_at)
select gen_random_uuid(), 'giris', s.product_id, s.location_id, s.quantity,
       u.id, 'Açılış stoğu', now() - interval '3 days'
from public.stock s
join auth.users u on u.email = 'sorumlu@example.com';

-- 8) KONTROL: sonuç tablosunda her satırda bir sayı görünmeli
select 'kullanıcı (profil)'    as kayit, count(*) as adet from public.profiles
union all select 'sorumlu',          count(*) from public.profiles where role = 'sorumlu'
union all select 'depo',             count(*) from public.warehouses
union all select 'raf',              count(*) from public.locations
union all select 'depo yetkisi',     count(*) from public.user_warehouses
union all select 'ürün',             count(*) from public.products
union all select 'stok satırı',      count(*) from public.stock
union all select 'hareket',          count(*) from public.stock_movements
union all select 'kritik ürün',      count(*) from public.critical_stock;
