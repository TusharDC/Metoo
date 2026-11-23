-- ============================================================================
-- Shararat — profile mutation RPCs
-- Give the client a clean API for writing enums / arrays / geography instead of
-- wrestling with those types over PostgREST. All scoped to auth.uid().
-- ============================================================================

-- Create or update the caller's profile. `complete` flips onboarding_complete.
create or replace function save_profile(
  p_display_name   text,
  p_date_of_birth  date,
  p_gender         text,
  p_bio            text default null,
  p_interested_in  text[] default '{}',
  p_min_age        int default 18,
  p_max_age        int default 60,
  p_max_distance_km int default 50,
  p_complete       boolean default false
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into profiles as pr (
    id, display_name, date_of_birth, gender, bio, interested_in,
    min_age, max_age, max_distance_km, onboarding_complete
  ) values (
    auth.uid(), p_display_name, p_date_of_birth, p_gender::gender, p_bio,
    (select coalesce(array_agg(x::gender), '{}') from unnest(p_interested_in) as x),
    p_min_age, p_max_age, p_max_distance_km, p_complete
  )
  on conflict (id) do update set
    display_name   = excluded.display_name,
    date_of_birth  = excluded.date_of_birth,
    gender         = excluded.gender,
    bio            = excluded.bio,
    interested_in  = excluded.interested_in,
    min_age        = excluded.min_age,
    max_age        = excluded.max_age,
    max_distance_km = excluded.max_distance_km,
    onboarding_complete = pr.onboarding_complete or excluded.onboarding_complete;
end; $$;

-- Update discovery preferences only (used by the Filters sheet).
create or replace function save_preferences(
  p_interested_in  text[],
  p_min_age        int,
  p_max_age        int,
  p_max_distance_km int
) returns void language plpgsql security definer set search_path = public as $$
begin
  update profiles set
    interested_in = (select coalesce(array_agg(x::gender), '{}') from unnest(p_interested_in) as x),
    min_age = p_min_age, max_age = p_max_age, max_distance_km = p_max_distance_km
  where id = auth.uid();
end; $$;

create or replace function set_my_location(p_lat double precision, p_lng double precision, p_city text default null)
returns void language sql security definer set search_path = public as $$
  update profiles
  set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      city = coalesce(p_city, city)
  where id = auth.uid();
$$;

-- Replace the caller's interests with the given slugs.
create or replace function set_my_interests(p_slugs text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from profile_interests where profile_id = auth.uid();
  insert into profile_interests(profile_id, interest_id)
  select auth.uid(), i.id from interests i where i.slug = any(p_slugs);
end; $$;

-- Return the caller's OWN full profile (includes DOB, prefs) for the edit screen.
create or replace function get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'date_of_birth', p.date_of_birth,
    'age', extract(year from age(p.date_of_birth))::int,
    'gender', p.gender,
    'bio', p.bio,
    'interested_in', to_jsonb(p.interested_in),
    'min_age', p.min_age,
    'max_age', p.max_age,
    'max_distance_km', p.max_distance_km,
    'city', p.city,
    'is_verified', p.is_verified,
    'is_discoverable', p.is_discoverable,
    'onboarding_complete', p.onboarding_complete,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'path', ph.storage_path, 'position', ph.position) order by ph.position)
                        from profile_photos ph where ph.profile_id = p.id), '[]'::jsonb),
    'interests', coalesce((select jsonb_agg(i.slug) from profile_interests pi join interests i on i.id = pi.interest_id where pi.profile_id = p.id), '[]'::jsonb),
    'interest_labels', coalesce((select jsonb_agg(i.label order by i.label) from profile_interests pi join interests i on i.id = pi.interest_id where pi.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p where p.id = auth.uid();
$$;

grant execute on function
  save_profile(text, date, text, text, text[], int, int, int, boolean),
  save_preferences(text[], int, int, int),
  set_my_location(double precision, double precision, text),
  set_my_interests(text[]),
  get_my_profile
to authenticated;
