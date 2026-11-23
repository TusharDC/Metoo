-- Interest tags used during onboarding / profile editing + discovery filtering.
insert into interests (slug, label) values
  ('travel','Travel'), ('music','Music'), ('movies','Movies'), ('fitness','Fitness'),
  ('foodie','Foodie'), ('gaming','Gaming'), ('reading','Reading'), ('art','Art'),
  ('photography','Photography'), ('cooking','Cooking'), ('dancing','Dancing'),
  ('coffee','Coffee'), ('pets','Pets'), ('nature','Nature'), ('yoga','Yoga'),
  ('tech','Tech'), ('fashion','Fashion'), ('sports','Sports'), ('nightlife','Nightlife'),
  ('spirituality','Spirituality')
on conflict (slug) do nothing;
