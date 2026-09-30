-- نظام الحضور والانصراف | شغّل هذا الملف كاملاً في Supabase > SQL Editor
create extension if not exists pgcrypto with schema extensions;

create table admins (email text primary key);

create table pharmacies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  lat float8, lng float8, radius_m int not null default 150,
  kiosk_key text not null default encode(extensions.gen_random_bytes(16),'hex'),
  secret text not null default encode(extensions.gen_random_bytes(32),'hex'),
  active bool not null default true
);

create table shifts (
  id uuid primary key default gen_random_uuid(),
  pharmacy_id uuid not null references pharmacies on delete cascade,
  name text not null,
  start_time time not null, end_time time not null,
  grace_min int not null default 15
);

create table employees (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  username text not null unique,
  password_hash text not null,
  phone text, job_title text,
  pharmacy_id uuid references pharmacies on delete set null,
  shift_id uuid references shifts on delete set null,
  device_id text,
  active bool not null default true,
  created_at timestamptz default now()
);

create table sessions (
  token text primary key default encode(extensions.gen_random_bytes(24),'hex'),
  employee_id uuid not null references employees on delete cascade,
  created_at timestamptz default now()
);

create table attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees on delete cascade,
  pharmacy_id uuid references pharmacies,
  shift_id uuid references shifts,
  work_date date not null,
  check_in timestamptz, check_out timestamptz,
  late_min int not null default 0, early_min int not null default 0,
  in_dist int, out_dist int,
  unique (employee_id, work_date)
);
create index on attendance (work_date, pharmacy_id);

-- الأمان: الأدمن فقط يصل للجداول مباشرة، والموظف عبر الدوال فقط
create function is_admin() returns bool language sql stable security definer set search_path=public as
$$ select exists(select 1 from admins where email = auth.jwt()->>'email') $$;

alter table admins enable row level security;
alter table pharmacies enable row level security;
alter table shifts enable row level security;
alter table employees enable row level security;
alter table sessions enable row level security;
alter table attendance enable row level security;
create policy a on pharmacies for all using (is_admin()) with check (is_admin());
create policy a on shifts for all using (is_admin()) with check (is_admin());
create policy a on employees for all using (is_admin()) with check (is_admin());
create policy a on attendance for all using (is_admin()) with check (is_admin());

-- رمز الـ QR المتغير (كل 30 ثانية)
create function win() returns bigint language sql stable as $$ select floor(extract(epoch from now())/30)::bigint $$;
create function tok(p uuid, w bigint) returns text language sql stable security definer set search_path=public,extensions as
$$ select substr(encode(hmac(w::text,(select secret from pharmacies where id=p),'sha256'),'hex'),1,16) $$;
revoke all on function win(), tok(uuid,bigint) from public, anon, authenticated;

create function kiosk_token(k text) returns json language plpgsql security definer set search_path=public as $$
declare r pharmacies; begin
  select * into r from pharmacies where kiosk_key=k and active;
  if r.id is null then raise exception 'مفتاح الشاشة غير صحيح'; end if;
  return json_build_object('p',r.id,'name',r.name,'t',tok(r.id,win()),'left',30-mod(extract(epoch from now())::int,30));
end $$;

create function emp_of(tk text) returns employees language sql stable security definer set search_path=public as
$$ select e.* from sessions s join employees e on e.id=s.employee_id
   where s.token=tk and e.active and s.created_at>now()-interval '30 days' $$;
revoke all on function emp_of(text) from public, anon, authenticated;

create function employee_login(u text, pw text, dev text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare e employees; t text; begin
  select * into e from employees where username=lower(u) and active and password_hash=crypt(pw,password_hash);
  if e.id is null then raise exception 'اسم المستخدم أو كلمة المرور غير صحيحة'; end if;
  if e.device_id is null then update employees set device_id=dev where id=e.id;
  elsif e.device_id<>dev then raise exception 'هذا الحساب مرتبط بجهاز آخر، راجع الإدارة'; end if;
  insert into sessions(employee_id) values (e.id) returning token into t;
  return json_build_object('token',t,'name',e.full_name);
end $$;

create function my_status(tk text) returns json language plpgsql security definer set search_path=public as $$
declare e employees; a attendance; begin
  e:=emp_of(tk); if e.id is null then raise exception 'انتهت الجلسة'; end if;
  select * into a from attendance where employee_id=e.id and work_date=(now() at time zone 'Asia/Baghdad')::date;
  return json_build_object('name',e.full_name,'in',a.check_in,'out',a.check_out);
end $$;

create function punch(tk text, p uuid, t text, lat float8, lng float8) returns json language plpgsql security definer set search_path=public,extensions as $$
declare e employees; ph pharmacies; s shifts; a attendance; d int:=0; nowt time; today date; late int:=0; early int:=0;
begin
  e:=emp_of(tk); if e.id is null then raise exception 'انتهت الجلسة، سجّل الدخول مجدداً'; end if;
  if e.pharmacy_id is distinct from p then raise exception 'هذا الرمز لصيدلية غير صيدليتك'; end if;
  if t is distinct from tok(p,win()) and t is distinct from tok(p,win()-1) then
    raise exception 'الرمز منتهي. امسح الرمز الحي من شاشة الصيدلية'; end if;
  select * into ph from pharmacies where id=p;
  if ph.lat is not null then
    if lat is null then raise exception 'يجب تفعيل الموقع (GPS)'; end if;
    d:=(2*6371000*asin(sqrt(power(sin(radians(lat-ph.lat)/2),2)+cos(radians(ph.lat))*cos(radians(lat))*power(sin(radians(lng-ph.lng)/2),2))))::int;
    if d>ph.radius_m then raise exception 'أنت خارج نطاق الصيدلية'; end if;
  end if;
  today:=(now() at time zone 'Asia/Baghdad')::date; nowt:=(now() at time zone 'Asia/Baghdad')::time;
  select * into s from shifts where id=e.shift_id;
  select * into a from attendance where employee_id=e.id and work_date=today;
  if a.id is null then
    if s.id is not null and nowt > s.start_time+make_interval(mins=>s.grace_min) then
      late:=floor(extract(epoch from nowt-s.start_time)/60); end if;
    insert into attendance(employee_id,pharmacy_id,shift_id,work_date,check_in,late_min,in_dist)
      values (e.id,p,e.shift_id,today,now(),late,d);
    return json_build_object('type','in','late',late,'time',to_char(nowt,'HH24:MI'));
  end if;
  if a.check_out is not null then raise exception 'تم تسجيل حضورك وانصرافك لهذا اليوم'; end if;
  if now()-a.check_in < interval '2 minutes' then raise exception 'تم تسجيل الحضور قبل لحظات'; end if;
  if s.id is not null and nowt < s.end_time then early:=floor(extract(epoch from s.end_time-nowt)/60); end if;
  update attendance set check_out=now(), early_min=early, out_dist=d where id=a.id;
  return json_build_object('type','out','early',early,'time',to_char(nowt,'HH24:MI'));
end $$;

-- دوال الأدمن
create function admin_add_employee(n text,u text,pw text,ph text,pid uuid,sid uuid,job text default null) returns uuid
language plpgsql security definer set search_path=public,extensions as $$
declare i uuid; begin
  if not is_admin() then raise exception 'غير مصرّح'; end if;
  insert into employees(full_name,username,password_hash,phone,pharmacy_id,shift_id,job_title)
  values (n,lower(u),crypt(pw,gen_salt('bf')),ph,pid,sid,job) returning id into i; return i;
end $$;
create function admin_set_password(eid uuid, pw text) returns void language plpgsql security definer set search_path=public,extensions as $$
begin if not is_admin() then raise exception 'غير مصرّح'; end if;
  update employees set password_hash=crypt(pw,gen_salt('bf')) where id=eid; delete from sessions where employee_id=eid; end $$;
create function admin_reset_device(eid uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'غير مصرّح'; end if;
  update employees set device_id=null where id=eid; delete from sessions where employee_id=eid; end $$;

-- بعد إنشاء حساب الأدمن من Authentication > Users أضف إيميله هنا:
-- insert into admins values ('you@example.com');

-- استعلام تقرير جاهز: مجموع التأخير والخروج المبكر لكل موظف في الشهر
-- select e.full_name, p.name pharmacy, count(*) days, sum(a.late_min) late_total, sum(a.early_min) early_total
-- from attendance a join employees e on e.id=a.employee_id join pharmacies p on p.id=a.pharmacy_id
-- where a.work_date >= date_trunc('month', now()) group by 1,2 order by late_total desc;
