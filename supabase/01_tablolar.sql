-- =====================================================================
-- CENG409 Mobil Depo ve Stok Takip Sistemi
-- Adım 1: Tablolar ve veri bütünlüğü kuralları
-- Supabase > SQL Editor > New query içine yapıştırıp "Run" ile çalıştırın.
-- =====================================================================

-- 1) KULLANICI PROFİLLERİ
-- E-posta/şifreyi Supabase Auth tutar; burada rol ve ad tutulur.
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null,
  role       text not null default 'personel'
             check (role in ('personel', 'sorumlu')),
  created_at timestamptz not null default now()
);

-- 2) DEPOLAR
create table public.warehouses (
  id         bigint generated always as identity primary key,
  code       text not null unique,
  name       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- 3) KULLANICI - DEPO YETKİSİ (çoka-çok ilişki)
create table public.user_warehouses (
  user_id      uuid   not null references public.profiles(id)   on delete cascade,
  warehouse_id bigint not null references public.warehouses(id) on delete cascade,
  primary key (user_id, warehouse_id)
);

-- 4) RAFLAR (her raf tek bir depoya aittir)
create table public.locations (
  id           bigint generated always as identity primary key,
  warehouse_id bigint not null references public.warehouses(id),
  code         text not null,
  is_active    boolean not null default true,
  unique (warehouse_id, code)            -- aynı depoda aynı raf kodu iki kez olamaz
);

-- 5) ÜRÜN KARTI
create table public.products (
  id             bigint generated always as identity primary key,
  code           text not null unique,   -- ürün kodu benzersiz
  name           text not null,
  unit           text not null check (unit in ('adet', 'koli', 'kg')),
  critical_level numeric not null default 0 check (critical_level >= 0),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

-- 6) ANLIK STOK (hangi rafta kaç tane var)
create table public.stock (
  product_id  bigint  not null references public.products(id),
  location_id bigint  not null references public.locations(id),
  quantity    numeric not null default 0 check (quantity >= 0),   -- negatif stok imkânsız
  updated_at  timestamptz not null default now(),
  primary key (product_id, location_id)
);

-- 7) TRANSFERLER (iki aşamalı: yolda -> teslim alındı)
create table public.transfers (
  id               bigint generated always as identity primary key,
  product_id       bigint  not null references public.products(id),
  from_location_id bigint  not null references public.locations(id),
  to_location_id   bigint  not null references public.locations(id),
  quantity         numeric not null check (quantity > 0),
  status           text    not null default 'yolda'
                   check (status in ('yolda', 'teslim_alindi', 'iptal')),
  created_by       uuid    not null references public.profiles(id),
  created_at       timestamptz not null default now(),
  received_by      uuid    references public.profiles(id),
  received_at      timestamptz,
  check (from_location_id <> to_location_id)                     -- kaynak ≠ hedef
);

-- 8) STOK HAREKETLERİ (defter: silinmez, değiştirilmez, sadece eklenir)
create table public.stock_movements (
  id               bigint generated always as identity primary key,
  request_id       uuid    not null unique,  -- çift gönderimi engeller
  type             text    not null
                   check (type in ('giris', 'cikis', 'transfer_cikis', 'transfer_giris', 'duzeltme')),
  product_id       bigint  not null references public.products(id),
  from_location_id bigint  references public.locations(id),
  to_location_id   bigint  references public.locations(id),
  quantity         numeric not null check (quantity > 0),
  user_id          uuid    not null references public.profiles(id),
  transfer_id      bigint  references public.transfers(id),
  note             text,
  created_at       timestamptz not null default now(),
  -- her hareket tek bir rafı etkiler: ya "nereden" ya "nereye" dolu
  check ((from_location_id is null) <> (to_location_id is null)),
  check (type not in ('giris', 'transfer_giris') or to_location_id   is not null),
  check (type not in ('cikis', 'transfer_cikis') or from_location_id is not null),
  check (type not in ('transfer_cikis', 'transfer_giris') or transfer_id is not null)
);

-- 9) SAYIMLAR (personel sayar, sorumlu onaylar)
create table public.stock_counts (
  id          bigint generated always as identity primary key,
  product_id  bigint  not null references public.products(id),
  location_id bigint  not null references public.locations(id),
  system_qty  numeric not null check (system_qty  >= 0),
  counted_qty numeric not null check (counted_qty >= 0),
  status      text    not null default 'bekliyor'
              check (status in ('bekliyor', 'onaylandi', 'reddedildi')),
  note        text,
  counted_by  uuid    not null references public.profiles(id),
  counted_at  timestamptz not null default now(),
  approved_by uuid    references public.profiles(id),
  approved_at timestamptz
);

-- Sık yapılan aramalar için indeksler
create index on public.stock_movements (product_id, created_at desc);
create index on public.stock_movements (user_id, created_at desc);
create index on public.transfers (status);
create index on public.stock_counts (status);

-- GÜVENLİK: tüm tablolarda Row Level Security açık.
-- Kurallar (politikalar) Adım 2'de eklenecek; o zamana kadar
-- uygulama tarafından hiçbir tabloya erişilemez (güvenli varsayılan).
alter table public.profiles        enable row level security;
alter table public.warehouses      enable row level security;
alter table public.user_warehouses enable row level security;
alter table public.locations       enable row level security;
alter table public.products        enable row level security;
alter table public.stock           enable row level security;
alter table public.transfers       enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_counts    enable row level security;
