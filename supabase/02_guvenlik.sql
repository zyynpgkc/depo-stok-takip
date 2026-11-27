-- Adım 2: Güvenlik kuralları (RLS) ve otomatik profil

-- Yardımcı fonksiyon: giriş yapan kullanıcı sorumlu mu?
create or replace function public.is_manager()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'sorumlu'
  );
$$;

-- Yardımcı fonksiyon: kullanıcı bu rafın deposunda yetkili mi?
create or replace function public.has_location_access(p_location_id bigint)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_manager() or exists (
    select 1
    from public.locations l
    join public.user_warehouses uw on uw.warehouse_id = l.warehouse_id
    where l.id = p_location_id and uw.user_id = auth.uid()
  );
$$;

-- Yeni kullanıcı kaydolunca otomatik "personel" profili oluştur
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- PROFİLLER: kendi profilini görür; sorumlu herkesi görür. Kimse rolünü değiştiremez.
create policy "profil_okuma" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_manager());

-- DEPOLAR ve RAFLAR: giriş yapan herkes okur
create policy "depo_okuma" on public.warehouses
  for select to authenticated using (true);

create policy "raf_okuma" on public.locations
  for select to authenticated using (true);

-- KULLANICI-DEPO YETKİSİ: kendi yetkilerini görür; sorumlu hepsini görür
create policy "yetki_okuma" on public.user_warehouses
  for select to authenticated
  using (user_id = auth.uid() or public.is_manager());

-- ÜRÜNLER: herkes okur; sadece sorumlu ekler ve günceller
create policy "urun_okuma" on public.products
  for select to authenticated using (true);

create policy "urun_ekleme_sorumlu" on public.products
  for insert to authenticated
  with check (public.is_manager());

create policy "urun_guncelleme_sorumlu" on public.products
  for update to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- STOK: herkes okur; doğrudan yazma YOK (sadece Adım 3 fonksiyonlarıyla)
create policy "stok_okuma" on public.stock
  for select to authenticated using (true);

-- TRANSFERLER: kaynak veya hedef deposunda yetkili olan görür
create policy "transfer_okuma" on public.transfers
  for select to authenticated
  using (public.has_location_access(from_location_id)
         or public.has_location_access(to_location_id));

-- HAREKETLER: kendi hareketlerini görür; sorumlu hepsini görür
create policy "hareket_okuma" on public.stock_movements
  for select to authenticated
  using (user_id = auth.uid() or public.is_manager());

-- SAYIMLAR: kendi sayımlarını görür; sorumlu hepsini görür
create policy "sayim_okuma" on public.stock_counts
  for select to authenticated
  using (counted_by = auth.uid() or public.is_manager());
