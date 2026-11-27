-- =====================================================================
-- Adım 3: Stok işlemi fonksiyonları (iş kuralları veritabanında)
-- Stok SADECE bu fonksiyonlarla değişir. Her fonksiyon:
--   * oturum, yetki, aktif ürün/raf ve miktar kontrolü yapar
--   * request_id ile çift gönderimi engeller
--   * stok satırını kilitleyerek (FOR UPDATE) eşzamanlı işlemi sıraya sokar
--   * stok değişikliği ile hareket kaydını birlikte yazar (ya hepsi ya hiçbiri)
-- =====================================================================

-- Ortak kontroller (giriş, çıkış ve transfer için)
create or replace function public._check_operation(
  p_product_id bigint, p_location_id bigint, p_quantity numeric)
returns void
language plpgsql stable security definer set search_path = public
as $$
declare
  v_unit text;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekiyor.';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Miktar sıfırdan büyük olmalı.';
  end if;

  select unit into v_unit from products where id = p_product_id and is_active;
  if v_unit is null then
    raise exception 'Ürün bulunamadı veya pasif durumda.';
  end if;
  if v_unit in ('adet', 'koli') and p_quantity <> trunc(p_quantity) then
    raise exception 'Bu ürünün birimi "%". Miktar tam sayı olmalı.', v_unit;
  end if;

  if not exists (select 1 from locations where id = p_location_id and is_active) then
    raise exception 'Raf bulunamadı veya pasif durumda.';
  end if;
  if not has_location_access(p_location_id) then
    raise exception 'Bu depoda işlem yapma yetkiniz yok.';
  end if;
end;
$$;


-- STOK GİRİŞİ -> yeni stok miktarını döndürür
create or replace function public.stock_in(
  p_request_id uuid, p_product_id bigint, p_location_id bigint,
  p_quantity numeric, p_note text default null)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare
  v_qty numeric;
begin
  -- Çift gönderim: aynı istek daha önce işlendiyse tekrar işleme
  if exists (select 1 from stock_movements where request_id = p_request_id) then
    select quantity into v_qty from stock
     where product_id = p_product_id and location_id = p_location_id;
    return coalesce(v_qty, 0);
  end if;

  perform _check_operation(p_product_id, p_location_id, p_quantity);

  insert into stock (product_id, location_id, quantity)
  values (p_product_id, p_location_id, p_quantity)
  on conflict (product_id, location_id)
  do update set quantity = stock.quantity + excluded.quantity, updated_at = now()
  returning quantity into v_qty;

  insert into stock_movements (request_id, type, product_id, to_location_id, quantity, user_id, note)
  values (p_request_id, 'giris', p_product_id, p_location_id, p_quantity, auth.uid(), p_note);

  return v_qty;
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- STOK ÇIKIŞI -> yeni stok miktarını döndürür
create or replace function public.stock_out(
  p_request_id uuid, p_product_id bigint, p_location_id bigint,
  p_quantity numeric, p_note text default null)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare
  v_qty  numeric;
  v_unit text;
begin
  if exists (select 1 from stock_movements where request_id = p_request_id) then
    select quantity into v_qty from stock
     where product_id = p_product_id and location_id = p_location_id;
    return coalesce(v_qty, 0);
  end if;

  perform _check_operation(p_product_id, p_location_id, p_quantity);
  select unit into v_unit from products where id = p_product_id;

  -- Satırı kilitle: aynı anda gelen ikinci işlem bu satırı bekler
  select quantity into v_qty from stock
   where product_id = p_product_id and location_id = p_location_id
   for update;

  if coalesce(v_qty, 0) < p_quantity then
    raise exception 'Yetersiz stok. Bu rafta mevcut: % %.', coalesce(v_qty, 0), v_unit;
  end if;

  update stock set quantity = quantity - p_quantity, updated_at = now()
   where product_id = p_product_id and location_id = p_location_id
  returning quantity into v_qty;

  insert into stock_movements (request_id, type, product_id, from_location_id, quantity, user_id, note)
  values (p_request_id, 'cikis', p_product_id, p_location_id, p_quantity, auth.uid(), p_note);

  return v_qty;
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- TRANSFER GÖNDER (1. aşama) -> transfer numarasını döndürür
-- Stok kaynaktan düşer, transfer "yolda" durumuna geçer.
create or replace function public.transfer_send(
  p_request_id uuid, p_product_id bigint, p_from_location_id bigint,
  p_to_location_id bigint, p_quantity numeric, p_note text default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_qty         numeric;
  v_unit        text;
  v_transfer_id bigint;
begin
  select transfer_id into v_transfer_id from stock_movements where request_id = p_request_id;
  if found then
    return v_transfer_id;
  end if;

  perform _check_operation(p_product_id, p_from_location_id, p_quantity);
  if p_from_location_id = p_to_location_id then
    raise exception 'Kaynak ve hedef raf aynı olamaz.';
  end if;
  if not exists (select 1 from locations where id = p_to_location_id and is_active) then
    raise exception 'Hedef raf bulunamadı veya pasif durumda.';
  end if;
  select unit into v_unit from products where id = p_product_id;

  select quantity into v_qty from stock
   where product_id = p_product_id and location_id = p_from_location_id
   for update;
  if coalesce(v_qty, 0) < p_quantity then
    raise exception 'Yetersiz stok. Kaynak rafta mevcut: % %.', coalesce(v_qty, 0), v_unit;
  end if;

  update stock set quantity = quantity - p_quantity, updated_at = now()
   where product_id = p_product_id and location_id = p_from_location_id;

  insert into transfers (product_id, from_location_id, to_location_id, quantity, created_by)
  values (p_product_id, p_from_location_id, p_to_location_id, p_quantity, auth.uid())
  returning id into v_transfer_id;

  insert into stock_movements (request_id, type, product_id, from_location_id, quantity, user_id, transfer_id, note)
  values (p_request_id, 'transfer_cikis', p_product_id, p_from_location_id, p_quantity, auth.uid(), v_transfer_id, p_note);

  return v_transfer_id;
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- TRANSFER TESLİM AL (2. aşama) -> hedef raftaki yeni stok miktarını döndürür
create or replace function public.transfer_receive(p_request_id uuid, p_transfer_id bigint)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare
  t     transfers%rowtype;
  v_qty numeric;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekiyor.';
  end if;

  select * into t from transfers where id = p_transfer_id for update;
  if not found then
    raise exception 'Transfer bulunamadı.';
  end if;

  if exists (select 1 from stock_movements where request_id = p_request_id) then
    select quantity into v_qty from stock
     where product_id = t.product_id and location_id = t.to_location_id;
    return coalesce(v_qty, 0);
  end if;

  if t.status <> 'yolda' then
    raise exception 'Bu transfer zaten "%" durumunda.', t.status;
  end if;
  if not has_location_access(t.to_location_id) then
    raise exception 'Hedef depoda teslim alma yetkiniz yok.';
  end if;

  insert into stock (product_id, location_id, quantity)
  values (t.product_id, t.to_location_id, t.quantity)
  on conflict (product_id, location_id)
  do update set quantity = stock.quantity + excluded.quantity, updated_at = now()
  returning quantity into v_qty;

  update transfers
     set status = 'teslim_alindi', received_by = auth.uid(), received_at = now()
   where id = t.id;

  insert into stock_movements (request_id, type, product_id, to_location_id, quantity, user_id, transfer_id)
  values (p_request_id, 'transfer_giris', t.product_id, t.to_location_id, t.quantity, auth.uid(), t.id);

  return v_qty;
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- TRANSFER İPTAL (sadece sorumlu) -> stok kaynak rafa geri döner
create or replace function public.transfer_cancel(p_request_id uuid, p_transfer_id bigint, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  t transfers%rowtype;
begin
  if not is_manager() then
    raise exception 'Transfer iptali için sorumlu yetkisi gerekiyor.';
  end if;
  if exists (select 1 from stock_movements where request_id = p_request_id) then
    return;
  end if;

  select * into t from transfers where id = p_transfer_id for update;
  if not found then
    raise exception 'Transfer bulunamadı.';
  end if;
  if t.status <> 'yolda' then
    raise exception 'Sadece "yolda" olan transfer iptal edilebilir. Şu anki durum: %', t.status;
  end if;

  insert into stock (product_id, location_id, quantity)
  values (t.product_id, t.from_location_id, t.quantity)
  on conflict (product_id, location_id)
  do update set quantity = stock.quantity + excluded.quantity, updated_at = now();

  update transfers set status = 'iptal' where id = t.id;

  insert into stock_movements (request_id, type, product_id, to_location_id, quantity, user_id, transfer_id, note)
  values (p_request_id, 'transfer_giris', t.product_id, t.from_location_id, t.quantity, auth.uid(), t.id,
          coalesce(p_note, 'Transfer iptal: kaynağa iade'));
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- SAYIM GİR (personel veya sorumlu) -> sayım numarasını döndürür
create or replace function public.count_submit(
  p_product_id bigint, p_location_id bigint, p_counted_qty numeric, p_note text default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_system numeric;
  v_id     bigint;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekiyor.';
  end if;
  if p_counted_qty is null or p_counted_qty < 0 then
    raise exception 'Sayılan miktar negatif olamaz.';
  end if;
  if not exists (select 1 from products where id = p_product_id and is_active) then
    raise exception 'Ürün bulunamadı veya pasif durumda.';
  end if;
  if not has_location_access(p_location_id) then
    raise exception 'Bu depoda işlem yapma yetkiniz yok.';
  end if;

  select quantity into v_system from stock
   where product_id = p_product_id and location_id = p_location_id;

  insert into stock_counts (product_id, location_id, system_qty, counted_qty, note, counted_by)
  values (p_product_id, p_location_id, coalesce(v_system, 0), p_counted_qty, p_note, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;


-- SAYIM ONAYLA / REDDET (sadece sorumlu)
-- Onaylanırsa sayımda bulunan fark kadar "duzeltme" hareketi yazılır.
create or replace function public.count_review(p_request_id uuid, p_count_id bigint, p_approve boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  c      stock_counts%rowtype;
  v_diff numeric;
  v_qty  numeric;
begin
  if not is_manager() then
    raise exception 'Sayım düzeltmesi için sorumlu yetkisi gerekiyor.';
  end if;

  select * into c from stock_counts where id = p_count_id for update;
  if not found then
    raise exception 'Sayım kaydı bulunamadı.';
  end if;
  if c.status <> 'bekliyor' then
    raise exception 'Bu sayım zaten "%" durumunda.', c.status;
  end if;

  if not p_approve then
    update stock_counts set status = 'reddedildi', approved_by = auth.uid(), approved_at = now()
     where id = c.id;
    return 'Sayım reddedildi.';
  end if;

  v_diff := c.counted_qty - c.system_qty;   -- sayımda bulunan fark

  if v_diff > 0 then
    insert into stock (product_id, location_id, quantity)
    values (c.product_id, c.location_id, v_diff)
    on conflict (product_id, location_id)
    do update set quantity = stock.quantity + excluded.quantity, updated_at = now();

    insert into stock_movements (request_id, type, product_id, to_location_id, quantity, user_id, note)
    values (p_request_id, 'duzeltme', c.product_id, c.location_id, v_diff, auth.uid(),
            'Sayım #' || c.id || ' fazlası');

  elsif v_diff < 0 then
    select quantity into v_qty from stock
     where product_id = c.product_id and location_id = c.location_id
     for update;
    if coalesce(v_qty, 0) < -v_diff then
      raise exception 'Düzeltme sonrası stok negatif olur (mevcut: %). Sayımı yenileyin.', coalesce(v_qty, 0);
    end if;

    update stock set quantity = quantity + v_diff, updated_at = now()
     where product_id = c.product_id and location_id = c.location_id;

    insert into stock_movements (request_id, type, product_id, from_location_id, quantity, user_id, note)
    values (p_request_id, 'duzeltme', c.product_id, c.location_id, -v_diff, auth.uid(),
            'Sayım #' || c.id || ' eksiği');
  end if;

  update stock_counts set status = 'onaylandi', approved_by = auth.uid(), approved_at = now()
   where id = c.id;

  return case when v_diff = 0 then 'Sayım onaylandı, fark yok.'
              else 'Sayım onaylandı, fark: ' || v_diff end;
exception
  when unique_violation then
    raise exception 'Bu işlem zaten kaydedildi (çift gönderim engellendi).';
end;
$$;


-- KRİTİK STOK GÖRÜNÜMÜ (ayrı tablo değil, hesaplanır)
create or replace view public.critical_stock
with (security_invoker = true) as
select p.id, p.code, p.name, p.unit, p.critical_level,
       coalesce(sum(s.quantity), 0) as total_quantity
from public.products p
left join public.stock s on s.product_id = p.id
where p.is_active
group by p.id
having coalesce(sum(s.quantity), 0) <= p.critical_level;


-- EN AZ YETKİ: giriş yapmamış kullanıcı (anon) hiçbir fonksiyonu çağıramaz
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;
