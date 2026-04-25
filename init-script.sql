-- showdan.clients definition

-- Drop table

-- DROP TABLE showdan.clients;
CREATE EXTENSION IF NOT EXISTS postgis;

-- Генерация старых версий UUID (если gen_random_uuid() недостаточно)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Дополнительные полезные штуки (опционально)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Включает модуль fuzzystrmatch (может пригодиться для поиска по именам исполнителей, если вы используете Levenshtein distance или триграммы)
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

CREATE SCHEMA showdan;

CREATE TYPE showdan."performer_type" AS ENUM (
    'conductor',
    'dj',
    'instrumental_soloist',
    'musical_collective',
    'vocal_soloist',
    'comic_standup'
);

CREATE TYPE showdan."media_type" AS ENUM (
    'photo',
    'video',
    'audio'
);

CREATE OR REPLACE FUNCTION showdan.increment_toxicity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE showdan.clients
    SET toxicityscore = COALESCE(toxicityscore, 0.0) + 0.1
    WHERE id = NEW.clientid;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TABLE showdan.clients (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	first_name varchar(100) NOT NULL,
	last_name varchar(100) NOT NULL,
	phone_number varchar(20) NOT NULL,
	toxicity_score float8 DEFAULT 0.0 NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT clients_phone_number_key UNIQUE (phone_number),
	CONSTRAINT clients_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_toxic_clients ON showdan.clients USING btree (toxicity_score) WHERE (toxicity_score >= (1.0)::double precision);


-- showdan.event_categories definition

-- Drop table

-- DROP TABLE showdan.event_categories;

CREATE TABLE showdan.event_categories (
	id serial4 NOT NULL,
	"name" varchar(100) NOT NULL,
	CONSTRAINT event_categories_name_key UNIQUE (name),
	CONSTRAINT event_categories_pkey PRIMARY KEY (id)
);


-- showdan.genres definition

-- Drop table

-- DROP TABLE showdan.genres;

CREATE TABLE showdan.genres (
	id serial4 NOT NULL,
	"name" varchar(100) NOT NULL,
	CONSTRAINT genres_name_key UNIQUE (name),
	CONSTRAINT genres_pkey PRIMARY KEY (id)
);


-- showdan.languages definition

-- Drop table

-- DROP TABLE showdan.languages;

CREATE TABLE showdan.languages (
	id serial4 NOT NULL,
	code varchar(5) NOT NULL,
	"name" varchar(50) NOT NULL,
	CONSTRAINT languages_code_key UNIQUE (code),
	CONSTRAINT languages_pkey PRIMARY KEY (id)
);


-- showdan.performers definition

-- Drop table

-- DROP TABLE showdan.performers;

CREATE TABLE showdan.performers (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	"type" showdan."performer_type" NOT NULL,
	first_name varchar(100) NOT NULL,
	last_name varchar(100) NOT NULL,
	stage_name varchar(150) NOT NULL,
	photo_url varchar(500) NULL,
	about varchar(1000) NULL,
	description text NULL,
	birth_date date NOT NULL,
	experience_years int2 NOT NULL,
	xp_points int4 DEFAULT 0 NULL,
	current_level int2 DEFAULT 1 NULL,
	hourly_rate numeric(10, 2) NULL,
	rating float8 DEFAULT 0.0 NULL,
	current_city_name varchar(100) NULL,
	location_point public.geometry(point, 4326) NULL,
	comm_language_ids _int4 DEFAULT '{}'::integer[] NULL,
	perf_language_ids _int4 DEFAULT '{}'::integer[] NULL,
	genre_ids _int4 DEFAULT '{}'::integer[] NULL,
	event_category_ids _int4 DEFAULT '{}'::integer[] NULL,
	specific_attributes jsonb DEFAULT '{}'::jsonb NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT chk_perf_langs_subset_of_comm CHECK ((perf_language_ids <@ comm_language_ids)),
	CONSTRAINT chk_real_experience CHECK (((EXTRACT(year FROM age((CURRENT_DATE)::timestamp with time zone, (birth_date)::timestamp with time zone)) - (experience_years)::numeric) >= (16)::numeric)),
	CONSTRAINT performers_pkey PRIMARY KEY (id, type)
)
PARTITION BY LIST (type);
CREATE INDEX idx_perf_attributes ON ONLY showdan.performers USING gin (specific_attributes);
CREATE INDEX idx_perf_comm_langs ON ONLY showdan.performers USING gin (comm_language_ids);
CREATE INDEX idx_perf_events ON ONLY showdan.performers USING gin (event_category_ids);
CREATE INDEX idx_perf_genres ON ONLY showdan.performers USING gin (genre_ids);
CREATE INDEX idx_perf_location ON ONLY showdan.performers USING gist (location_point);
CREATE INDEX idx_perf_perf_langs ON ONLY showdan.performers USING gin (perf_language_ids);


-- showdan.bookings definition

-- Drop table

-- DROP TABLE showdan.bookings;

CREATE TABLE showdan.bookings (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	performer_id uuid NOT NULL,
	"performer_type" showdan."performer_type" NOT NULL,
	client_id uuid NULL,
	event_type_id int4 NULL,
	city_id int4 NULL,
	start_time timestamptz NOT NULL,
	end_time timestamptz NOT NULL,
	status varchar(50) DEFAULT 'PENDING'::character varying NULL,
	is_tentative bool DEFAULT false NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT bookings_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_bookings_time ON showdan.bookings USING brin (start_time);


-- showdan.order_complaints definition

-- Drop table

-- DROP TABLE showdan.order_complaints;

CREATE TABLE showdan.order_complaints (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	booking_id uuid NULL,
	client_id uuid NULL,
	reason text NOT NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT order_complaints_pkey PRIMARY KEY (id)
);

-- Table Triggers

create trigger trg_complaint_toxicity after
insert
    on
    showdan.order_complaints for each row execute function increment_toxicity();


-- showdan.performer_rules definition

-- Drop table

-- DROP TABLE showdan.performer_rules;

CREATE TABLE showdan.performer_rules (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	performer_id uuid NOT NULL,
	"performer_type" showdan."performer_type" NOT NULL,
	rule_category varchar(100) NOT NULL,
	rule_text text NOT NULL,
	CONSTRAINT performer_rules_pkey PRIMARY KEY (id)
);


-- showdan.portfolio_media definition

-- Drop table

-- DROP TABLE showdan.portfolio_media;

CREATE TABLE showdan.portfolio_media (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	performer_id uuid NOT NULL,
	"performer_type" showdan."performer_type" NOT NULL,
	"media_type" showdan."media_type" NOT NULL,
	url varchar(500) NOT NULL,
	title varchar(200) NULL,
	duration_sec int4 NULL,
	CONSTRAINT portfolio_media_pkey PRIMARY KEY (id)
);


-- showdan.reviews definition

-- Drop table

-- DROP TABLE showdan.reviews;

CREATE TABLE showdan.reviews (
	id uuid DEFAULT uuid_generate_v4() NOT NULL,
	performer_id uuid NOT NULL,
	"performer_type" showdan."performer_type" NOT NULL,
	client_id uuid NULL,
	rating float8 NULL,
	review_text text NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT reviews_pkey PRIMARY KEY (id),
	CONSTRAINT reviews_rating_check CHECK (((rating >= (1.0)::double precision) AND (rating <= (5.0)::double precision)))
);


-- showdan.bookings foreign keys

ALTER TABLE showdan.bookings ADD CONSTRAINT bookings_client_id_fkey FOREIGN KEY (client_id) REFERENCES showdan.clients(id) ON DELETE CASCADE;
ALTER TABLE showdan.bookings ADD CONSTRAINT bookings_event_type_id_fkey FOREIGN KEY (event_type_id) REFERENCES showdan.event_categories(id);
ALTER TABLE showdan.bookings ADD CONSTRAINT fk_performer FOREIGN KEY (performer_id,"performer_type") REFERENCES showdan.performers(id,"type") ON DELETE CASCADE;


-- showdan.order_complaints foreign keys

ALTER TABLE showdan.order_complaints ADD CONSTRAINT order_complaints_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES showdan.bookings(id) ON DELETE CASCADE;
ALTER TABLE showdan.order_complaints ADD CONSTRAINT order_complaints_client_id_fkey FOREIGN KEY (client_id) REFERENCES showdan.clients(id) ON DELETE CASCADE;


-- showdan.performer_rules foreign keys

ALTER TABLE showdan.performer_rules ADD CONSTRAINT fk_performer_rules FOREIGN KEY (performer_id,"performer_type") REFERENCES showdan.performers(id,"type") ON DELETE CASCADE;


-- showdan.portfolio_media foreign keys

ALTER TABLE showdan.portfolio_media ADD CONSTRAINT fk_performer_media FOREIGN KEY (performer_id,"performer_type") REFERENCES showdan.performers(id,"type") ON DELETE CASCADE;


-- showdan.reviews foreign keys

ALTER TABLE showdan.reviews ADD CONSTRAINT fk_performer_review FOREIGN KEY (performer_id,"performer_type") REFERENCES showdan.performers(id,"type") ON DELETE CASCADE;
ALTER TABLE showdan.reviews ADD CONSTRAINT reviews_client_id_fkey FOREIGN KEY (client_id) REFERENCES showdan.clients(id) ON DELETE CASCADE;

INSERT INTO showdan.event_categories ("name") VALUES
	 ('Wedding'),
	 ('Corporate Event'),
	 ('Anniversary / Birthday'),
	 ('Graduation'),
	 ('Conference / Forum'),
	 ('Presentation / Exhibition'),
	 ('Concert / Festival'),
	 ('New Year Party'),
	 ('Teambuilding'),
	 ('Private Party / VIP');
INSERT INTO showdan.event_categories ("name") VALUES
	 ('Kids Party');
INSERT INTO showdan.genres ("name") VALUES
	 ('Classical Compere'),
	 ('Stand-up'),
	 ('Improvisation'),
	 ('Interactive'),
	 ('Official (Protocol)'),
	 ('Comedy'),
	 ('Intellectual / Quiz'),
	 ('Chamber / Soulful'),
	 ('Energetic / Club'),
	 ('Theatrical');
INSERT INTO showdan.genres ("name") VALUES
	 ('Pop / Estrada'),
	 ('Jazz / Lounge'),
	 ('Rock / Indie'),
	 ('Electronic Music (EDM)'),
	 ('Folk / Ethnic');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('aa','Afar'),
	 ('ab','Abkhazian'),
	 ('ae','Avestan'),
	 ('af','Afrikaans'),
	 ('ak','Akan'),
	 ('am','Amharic'),
	 ('an','Aragonese'),
	 ('ar','Arabic'),
	 ('as','Assamese'),
	 ('av','Avaric');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('ay','Aymara'),
	 ('az','Azerbaijani'),
	 ('ba','Bashkir'),
	 ('be','Belarusian'),
	 ('bg','Bulgarian'),
	 ('bh','Bihari languages'),
	 ('bi','Bislama'),
	 ('bm','Bambara'),
	 ('bn','Bengali'),
	 ('bo','Tibetan');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('br','Breton'),
	 ('bs','Bosnian'),
	 ('ca','Catalan'),
	 ('ce','Chechen'),
	 ('ch','Chamorro'),
	 ('co','Corsican'),
	 ('cr','Cree'),
	 ('cs','Czech'),
	 ('cu','Church Slavic'),
	 ('cv','Chuvash');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('cy','Welsh'),
	 ('da','Danish'),
	 ('de','German'),
	 ('dv','Divehi'),
	 ('dz','Dzongkha'),
	 ('ee','Ewe'),
	 ('el','Greek'),
	 ('en','English'),
	 ('eo','Esperanto'),
	 ('es','Spanish');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('et','Estonian'),
	 ('eu','Basque'),
	 ('fa','Persian'),
	 ('ff','Fulah'),
	 ('fi','Finnish'),
	 ('fj','Fijian'),
	 ('fo','Faroese'),
	 ('fr','French'),
	 ('fy','Western Frisian'),
	 ('ga','Irish');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('gd','Gaelic'),
	 ('gl','Galician'),
	 ('gn','Guarani'),
	 ('gu','Gujarati'),
	 ('gv','Manx'),
	 ('ha','Hausa'),
	 ('he','Hebrew'),
	 ('hi','Hindi'),
	 ('ho','Hiri Motu'),
	 ('hr','Croatian');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('ht','Haitian'),
	 ('hu','Hungarian'),
	 ('hy','Armenian'),
	 ('hz','Herero'),
	 ('ia','Interlingua'),
	 ('id','Indonesian'),
	 ('ie','Interlingue'),
	 ('ig','Igbo'),
	 ('ii','Sichuan Yi'),
	 ('ik','Inupiaq');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('io','Ido'),
	 ('is','Icelandic'),
	 ('it','Italian'),
	 ('iu','Inuktitut'),
	 ('ja','Japanese'),
	 ('jv','Javanese'),
	 ('ka','Georgian'),
	 ('kg','Kongo'),
	 ('ki','Kikuyu'),
	 ('kj','Kuanyama');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('kk','Kazakh'),
	 ('kl','Kalaallisut'),
	 ('km','Central Khmer'),
	 ('kn','Kannada'),
	 ('ko','Korean'),
	 ('kr','Kanuri'),
	 ('ks','Kashmiri'),
	 ('ku','Kurdish'),
	 ('kv','Komi'),
	 ('kw','Cornish');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('ky','Kirghiz'),
	 ('la','Latin'),
	 ('lb','Luxembourgish'),
	 ('lg','Ganda'),
	 ('li','Limburgan'),
	 ('ln','Lingala'),
	 ('lo','Lao'),
	 ('lt','Lithuanian'),
	 ('lu','Luba-Katanga'),
	 ('lv','Latvian');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('mg','Malagasy'),
	 ('mh','Marshallese'),
	 ('mi','Maori'),
	 ('mk','Macedonian'),
	 ('ml','Malayalam'),
	 ('mn','Mongolian'),
	 ('mr','Marathi'),
	 ('ms','Malay'),
	 ('mt','Maltese'),
	 ('my','Burmese');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('na','Nauru'),
	 ('nb','Norwegian Bokmål'),
	 ('nd','North Ndebele'),
	 ('ne','Nepali'),
	 ('ng','Ndonga'),
	 ('nl','Dutch'),
	 ('nn','Norwegian Nynorsk'),
	 ('no','Norwegian'),
	 ('nr','South Ndebele'),
	 ('nv','Navajo');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('ny','Chichewa'),
	 ('oc','Occitan'),
	 ('oj','Ojibwa'),
	 ('om','Oromo'),
	 ('or','Oriya'),
	 ('os','Ossetic'),
	 ('pa','Punjabi'),
	 ('pi','Pali'),
	 ('pl','Polish'),
	 ('ps','Pashto');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('pt','Portuguese'),
	 ('qu','Quechua'),
	 ('rm','Romansh'),
	 ('rn','Rundi'),
	 ('ro','Romanian'),
	 ('ru','Russian'),
	 ('rw','Kinyarwanda'),
	 ('sa','Sanskrit'),
	 ('sc','Sardinian'),
	 ('sd','Sindhi');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('se','Northern Sami'),
	 ('sg','Sango'),
	 ('si','Sinhala'),
	 ('sk','Slovak'),
	 ('sl','Slovenian'),
	 ('sm','Samoan'),
	 ('sn','Shona'),
	 ('so','Somali'),
	 ('sq','Albanian'),
	 ('sr','Serbian');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('ss','Swati'),
	 ('st','Southern Sotho'),
	 ('su','Sundanese'),
	 ('sv','Swedish'),
	 ('sw','Swahili'),
	 ('ta','Tamil'),
	 ('te','Telugu'),
	 ('tg','Tajik'),
	 ('th','Thai'),
	 ('ti','Tigrinya');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('tk','Turkmen'),
	 ('tl','Tagalog'),
	 ('tn','Tswana'),
	 ('to','Tonga'),
	 ('tr','Turkish'),
	 ('ts','Tsonga'),
	 ('tt','Tatar'),
	 ('tw','Twi'),
	 ('ty','Tahitian'),
	 ('ug','Uighur');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('uk','Ukrainian'),
	 ('ur','Urdu'),
	 ('uz','Uzbek'),
	 ('ve','Venda'),
	 ('vi','Vietnamese'),
	 ('vo','Volapük'),
	 ('wa','Walloon'),
	 ('wo','Wolof'),
	 ('xh','Xhosa'),
	 ('yi','Yiddish');
INSERT INTO showdan.languages (code,"name") VALUES
	 ('yo','Yoruba'),
	 ('za','Zhuang'),
	 ('zh','Chinese'),
	 ('zu','Zulu');

CREATE TABLE showdan.performers_conductor PARTITION OF showdan.performers FOR VALUES IN ('conductor');
CREATE TABLE showdan.performers_dj PARTITION OF showdan.performers FOR VALUES IN ('dj');
CREATE TABLE showdan.performers_instrumental_soloist PARTITION OF showdan.performers FOR VALUES IN ('instrumental_soloist');
CREATE TABLE showdan.performers_musical_collective PARTITION OF showdan.performers FOR VALUES IN ('musical_collective');
CREATE TABLE showdan.performers_vocal_soloist PARTITION OF showdan.performers FOR VALUES IN ('vocal_soloist');
CREATE TABLE showdan.performers_comic_standup PARTITION OF showdan.performers FOR VALUES IN ('comic_standup');

INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000001'::uuid,'conductor'::showdan."performer_type",'Oliver','Anderson','Oliver Anderson (Ведущий)','https://randomuser.me/api/portraits/men/85.jpg','Oliver Anderson (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2005-10-20',3,98104,98,622.56,4.7,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{1,6,9}','{6}','{1,3,7}','{2,5,6}','{"is_mc": true, "work_style": "SCRIPTWRITER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000007'::uuid,'conductor'::showdan."performer_type",'Olivia','Taylor','Olivia Taylor (Ведущий)','https://randomuser.me/api/portraits/men/93.jpg','Olivia Taylor (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1975-01-25',3,12332,12,129.60,4.7,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{3,4,6}','{4,6}','{4}','{3,4,5,9,10}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000013'::uuid,'conductor'::showdan."performer_type",'Harper','Martinez','Harper Martinez (Ведущий)','https://randomuser.me/api/portraits/men/88.jpg','Harper Martinez (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1996-07-09',9,8162,8,335.96,4.8,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{3,6}','{3,6}','{4,8,10}','{5,6,9}','{"is_mc": true, "work_style": "SCRIPTWRITER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000019'::uuid,'conductor'::showdan."performer_type",'Charlotte','Clark','Charlotte Clark (Ведущий)','https://randomuser.me/api/portraits/women/25.jpg','Charlotte Clark (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1971-08-08',36,11592,11,599.13,4.2,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{1,2,3}','{3}','{1,6,7}','{1,2,8,10}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000025'::uuid,'conductor'::showdan."performer_type",'Taylor','Jones','Taylor Jones (Ведущий)','https://randomuser.me/api/portraits/men/60.jpg','Taylor Jones (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1987-12-22',11,18812,18,532.27,4.2,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{4,7}','{7}','{4}','{4,5,6,8}','{"is_mc": true, "work_style": "SCRIPTWRITER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000031'::uuid,'conductor'::showdan."performer_type",'Mia','Miller','Mia Miller (Ведущий)','https://randomuser.me/api/portraits/women/70.jpg','Mia Miller (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1978-01-16',11,30074,30,594.87,4.0,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{5,6}','{5}','{1}','{2,5}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000037'::uuid,'conductor'::showdan."performer_type",'Elijah','Johnson','Elijah Johnson (Ведущий)','https://randomuser.me/api/portraits/women/21.jpg','Elijah Johnson (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2000-06-01',8,3429,3,347.96,4.0,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{5,6,8}','{5}','{4,5,6}','{3,9}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000043'::uuid,'conductor'::showdan."performer_type",'Mia','Jones','Mia Jones (Ведущий)','https://randomuser.me/api/portraits/women/83.jpg','Mia Jones (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1977-09-24',17,19617,19,174.95,4.8,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{2,3,4}','{3,4}','{1,4,5}','{2,5,6,8}','{"is_mc": true, "work_style": "SCRIPTWRITER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000049'::uuid,'conductor'::showdan."performer_type",'Mateo','White','Mateo White (Ведущий)','https://randomuser.me/api/portraits/women/17.jpg','Mateo White (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1976-02-22',4,41810,41,459.41,4.2,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{7,10}','{7,10}','{8}','{2,3,5,9,10}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000055'::uuid,'conductor'::showdan."performer_type",'Ethan','Lewis','Ethan Lewis (Ведущий)','https://randomuser.me/api/portraits/women/94.jpg','Ethan Lewis (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1971-12-14',6,68297,68,438.35,4.5,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{1}','{1}','{10}','{1,2,6,8,9}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000061'::uuid,'conductor'::showdan."performer_type",'Ava','Smith','Ava Smith (Ведущий)','https://randomuser.me/api/portraits/women/90.jpg','Ava Smith (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1990-08-13',1,68919,68,550.65,4.4,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{6}','{6}','{1,6,8}','{1,2,5,10}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000067'::uuid,'conductor'::showdan."performer_type",'Sophia','Miller','Sophia Miller (Ведущий)','https://randomuser.me/api/portraits/men/23.jpg','Sophia Miller (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1996-04-06',8,77668,77,547.92,4.2,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{6}','{6}','{3,6,7}','{8,9}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000073'::uuid,'conductor'::showdan."performer_type",'Emma','Garcia','Emma Garcia (Ведущий)','https://randomuser.me/api/portraits/men/38.jpg','Emma Garcia (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1975-05-23',15,10667,10,558.61,4.3,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{8}','{8}','{1,3,8}','{1,3,5,6,8}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000079'::uuid,'conductor'::showdan."performer_type",'Emily','Young','Emily Young (Ведущий)','https://randomuser.me/api/portraits/women/34.jpg','Emily Young (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1979-12-04',23,51403,51,158.29,4.9,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{4,8}','{8}','{1,6}','{2,3,4,8,9}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000085'::uuid,'conductor'::showdan."performer_type",'Mia','Martin','Mia Martin (Ведущий)','https://randomuser.me/api/portraits/women/29.jpg','Mia Martin (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2005-08-25',2,82278,82,616.75,4.6,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{2,7}','{7}','{3,5}','{1,3,5,8}','{"is_mc": true, "work_style": "SCRIPTWRITER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000091'::uuid,'conductor'::showdan."performer_type",'Emma','Davis','Emma Davis (Ведущий)','https://randomuser.me/api/portraits/men/8.jpg','Emma Davis (Ведущий) — профессионал в своей сфере. Работает в Berlin.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1986-06-12',11,59839,59,370.01,4.1,'Berlin','SRID=4326;POINT (13.405 52.52)'::public.geometry,'{9}','{9}','{4,7}','{2,5}','{"is_mc": true, "work_style": "UNIVERSAL"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000097'::uuid,'conductor'::showdan."performer_type",'Charlotte','White','Charlotte White (Ведущий)','https://randomuser.me/api/portraits/women/16.jpg','Charlotte White (Ведущий) — профессионал в своей сфере. Работает в New York.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1999-04-26',7,41365,41,797.54,4.1,'New York','SRID=4326;POINT (-74.006 40.7128)'::public.geometry,'{7,9}','{7}','{3}','{1,3,5,6,8}','{"is_mc": true, "work_style": "IMPROVISER"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000002'::uuid,'dj'::showdan."performer_type",'Emily','Rodriguez','DJ Rodriguez','https://randomuser.me/api/portraits/men/42.jpg','DJ Rodriguez — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1984-07-25',17,6507,6,184.56,4.8,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{8}','{8}','{9,14}','{1,2,7,10}','{"dj_type": "LOYAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000008'::uuid,'dj'::showdan."performer_type",'Evelyn','Taylor','DJ Taylor','https://randomuser.me/api/portraits/men/31.jpg','DJ Taylor — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2001-12-02',4,43218,43,559.88,4.1,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{1,7,10}','{10}','{11,14}','{2,7,10}','{"dj_type": "LOYAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000014'::uuid,'dj'::showdan."performer_type",'Amelia','Wilson','DJ Wilson','https://randomuser.me/api/portraits/women/88.jpg','DJ Wilson — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1971-05-05',15,98151,98,496.06,4.2,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{2,5}','{2}','{9,11,14}','{1,4,10}','{"dj_type": "PRINCIPAL_DJ"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000020'::uuid,'dj'::showdan."performer_type",'Abigail','Lewis','DJ Lewis','https://randomuser.me/api/portraits/men/69.jpg','DJ Lewis — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2004-03-25',4,8825,8,138.18,4.6,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{2,9}','{2,9}','{14}','{2,4,8}','{"dj_type": "PRINCIPAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000026'::uuid,'dj'::showdan."performer_type",'Abigail','Wilson','DJ Wilson','https://randomuser.me/api/portraits/men/18.jpg','DJ Wilson — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1976-09-04',19,66100,66,343.55,4.7,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{4,8,10}','{4,8}','{9,11,14}','{1,2,8,10}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000032'::uuid,'dj'::showdan."performer_type",'Harper','Brown','DJ Brown','https://randomuser.me/api/portraits/men/64.jpg','DJ Brown — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1972-01-10',35,58868,58,707.97,4.3,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{2,8,10}','{8,10}','{9}','{1,4,7,8,10}','{"dj_type": "LOYAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000038'::uuid,'dj'::showdan."performer_type",'Alex','Harris','DJ Harris','https://randomuser.me/api/portraits/women/28.jpg','DJ Harris — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1982-03-28',22,57784,57,700.56,4.6,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{1,6,10}','{6}','{9,11,14}','{1,4,8}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000044'::uuid,'dj'::showdan."performer_type",'Lily','Wilson','DJ Wilson','https://randomuser.me/api/portraits/women/54.jpg','DJ Wilson — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2004-01-24',5,94863,94,183.10,4.9,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{9}','{9}','{11,14}','{2,7,8,10}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000050'::uuid,'dj'::showdan."performer_type",'Abigail','Lewis','DJ Lewis','https://randomuser.me/api/portraits/men/63.jpg','DJ Lewis — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1985-11-22',2,39039,39,734.26,4.3,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{5,6}','{6}','{9,14}','{4,7}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000056'::uuid,'dj'::showdan."performer_type",'Olivia','Jones','DJ Jones','https://randomuser.me/api/portraits/men/45.jpg','DJ Jones — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1998-09-03',9,92611,92,162.78,4.9,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{3,5}','{3,5}','{9}','{1,4,7,8,10}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000062'::uuid,'dj'::showdan."performer_type",'Jordan','Johnson','DJ Johnson','https://randomuser.me/api/portraits/men/75.jpg','DJ Johnson — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2003-07-14',5,86643,86,528.96,4.2,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{4,8}','{4,8}','{9,11,14}','{1,4,7,8}','{"dj_type": "PRINCIPAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000068'::uuid,'dj'::showdan."performer_type",'Mason','Miller','DJ Miller','https://randomuser.me/api/portraits/women/18.jpg','DJ Miller — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1975-03-25',7,21725,21,452.18,4.5,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{3,5,9}','{9}','{9,11,14}','{1,2,4,7,8}','{"dj_type": "PRINCIPAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000074'::uuid,'dj'::showdan."performer_type",'Grace','Miller','DJ Miller','https://randomuser.me/api/portraits/women/10.jpg','DJ Miller — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1997-10-11',8,19695,19,690.53,4.9,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{4}','{4}','{9,11,14}','{4,7,8,10}','{"dj_type": "PRINCIPAL_DJ"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000080'::uuid,'dj'::showdan."performer_type",'Oliver','Smith','DJ Smith','https://randomuser.me/api/portraits/men/50.jpg','DJ Smith — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1998-12-09',3,83444,83,466.22,4.4,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{7}','{7}','{9}','{1,4,7,8,10}','{"dj_type": "LOYAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000086'::uuid,'dj'::showdan."performer_type",'Liam','Lee','DJ Lee','https://randomuser.me/api/portraits/men/36.jpg','DJ Lee — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1989-04-02',15,4750,4,432.38,4.5,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{4,5,6}','{4,6}','{9,11,14}','{1,2,4,8,10}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000092'::uuid,'dj'::showdan."performer_type",'Oliver','Martin','DJ Martin','https://randomuser.me/api/portraits/men/97.jpg','DJ Martin — профессионал в своей сфере. Работает в Madrid.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2000-07-17',7,17359,17,696.16,4.7,'Madrid','SRID=4326;POINT (-3.7038 40.4168)'::public.geometry,'{1,3,9}','{3}','{9,11,14}','{1,2,7,8}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000098'::uuid,'dj'::showdan."performer_type",'Mateo','Garcia','DJ Garcia','https://randomuser.me/api/portraits/men/10.jpg','DJ Garcia — профессионал в своей сфере. Работает в Los Angeles.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1997-05-23',7,38390,38,678.74,4.6,'Los Angeles','SRID=4326;POINT (-118.2437 34.0522)'::public.geometry,'{6}','{6}','{9,11,14}','{2,4,7,10}','{"dj_type": "UNIVERSAL_DJ"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000003'::uuid,'instrumental_soloist'::showdan."performer_type",'Emma','Taylor','Emma (Саксофон/Скрипка)','https://randomuser.me/api/portraits/men/25.jpg','Emma (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1982-06-01',9,78433,78,245.30,4.7,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{10}','{10}','{8,11,12}','{1,2,6,7,8}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "BRASS_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000009'::uuid,'instrumental_soloist'::showdan."performer_type",'Oliver','Perez','Oliver (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/68.jpg','Oliver (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1982-07-08',20,7375,7,623.07,5.0,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{3,7}','{3,7}','{12}','{1,6,7,8}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000015'::uuid,'instrumental_soloist'::showdan."performer_type",'Lily','Moore','Lily (Саксофон/Скрипка)','https://randomuser.me/api/portraits/men/58.jpg','Lily (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1973-05-19',13,65659,65,767.07,4.9,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{1,9}','{1,9}','{8,11,12}','{6,7,8,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000021'::uuid,'instrumental_soloist'::showdan."performer_type",'Taylor','Clark','Taylor (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/52.jpg','Taylor (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1984-11-17',14,7728,7,677.79,4.1,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{4}','{4}','{15}','{2,3,6}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000027'::uuid,'instrumental_soloist'::showdan."performer_type",'Mason','Wilson','Mason (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/42.jpg','Mason (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1971-04-24',2,70821,70,602.12,4.1,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{5,10}','{5,10}','{8,12,15}','{1,3,6,8,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000033'::uuid,'instrumental_soloist'::showdan."performer_type",'Ava','Harris','Ava (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/26.jpg','Ava (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1986-09-10',4,81815,81,608.20,4.2,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{3,4,5}','{4,5}','{12}','{1,2,6,7,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "KEYBOARD_SOLO"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000039'::uuid,'instrumental_soloist'::showdan."performer_type",'Harper','Martin','Harper (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/73.jpg','Harper (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1999-03-23',8,72284,72,384.97,4.9,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{6,10}','{10}','{8,12,15}','{3,6,7,8,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "BRASS_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000045'::uuid,'instrumental_soloist'::showdan."performer_type",'Oliver','Lewis','Oliver (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/8.jpg','Oliver (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1988-08-15',4,38073,38,628.45,4.0,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{8,9}','{8,9}','{11,12,15}','{1,2,3,6,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "BRASS_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000051'::uuid,'instrumental_soloist'::showdan."performer_type",'Abigail','Moore','Abigail (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/76.jpg','Abigail (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2001-03-10',8,79077,79,750.11,4.9,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{6}','{6}','{8,12,15}','{1,8}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "KEYBOARD_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000057'::uuid,'instrumental_soloist'::showdan."performer_type",'Mason','Davis','Mason (Саксофон/Скрипка)','https://randomuser.me/api/portraits/men/19.jpg','Mason (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2005-04-14',4,33941,33,664.66,4.6,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{3,7,8}','{3}','{8}','{1,3,6}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000063'::uuid,'instrumental_soloist'::showdan."performer_type",'Elijah','Miller','Elijah (Саксофон/Скрипка)','https://randomuser.me/api/portraits/men/72.jpg','Elijah (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1977-05-15',5,34115,34,792.31,4.1,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{1,3,10}','{1,3,10}','{8}','{1,2,6,8}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000069'::uuid,'instrumental_soloist'::showdan."performer_type",'Alex','Johnson','Alex (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/22.jpg','Alex (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1990-11-25',14,71700,71,350.76,4.3,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{5,8}','{5,8}','{8,12,15}','{3,8,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000075'::uuid,'instrumental_soloist'::showdan."performer_type",'Evelyn','Johnson','Evelyn (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/53.jpg','Evelyn (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1987-05-12',8,66486,66,231.44,4.2,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{1,3,8}','{3,8}','{8,11,12}','{1,2,6,7}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "KEYBOARD_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000081'::uuid,'instrumental_soloist'::showdan."performer_type",'Emily','Williams','Emily (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/31.jpg','Emily (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1973-02-05',12,6410,6,785.47,4.4,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{2}','{2}','{15}','{1,2,3,6,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "KEYBOARD_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000087'::uuid,'instrumental_soloist'::showdan."performer_type",'Olivia','Thompson','Olivia (Саксофон/Скрипка)','https://randomuser.me/api/portraits/men/89.jpg','Olivia (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1993-02-23',4,19308,19,173.53,4.4,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{3}','{3}','{8,12}','{1,2,3,7}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000093'::uuid,'instrumental_soloist'::showdan."performer_type",'Sam','Rodriguez','Sam (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/86.jpg','Sam (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Rome.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2002-05-23',6,40359,40,302.85,4.7,'Rome','SRID=4326;POINT (12.4964 41.9028)'::public.geometry,'{8}','{8}','{11,12}','{3,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "STRING_SOLO"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000099'::uuid,'instrumental_soloist'::showdan."performer_type",'Jordan','Rodriguez','Jordan (Саксофон/Скрипка)','https://randomuser.me/api/portraits/women/11.jpg','Jordan (Саксофон/Скрипка) — профессионал в своей сфере. Работает в Chicago.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1978-11-28',13,41673,41,272.22,4.8,'Chicago','SRID=4326;POINT (-87.6298 41.8781)'::public.geometry,'{2,4,7}','{2,4}','{11}','{1,3,7,8,10}','{"repertoire": ["Jazz", "Lounge"], "instrument_type": "BRASS_SOLO"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000004'::uuid,'musical_collective'::showdan."performer_type",'Amelia','Garcia','Группа Garcia Band','https://randomuser.me/api/portraits/men/46.jpg','Группа Garcia Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1995-12-13',13,28292,28,705.58,4.1,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{1,5,9}','{1,5,9}','{13}','{1,8}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000010'::uuid,'musical_collective'::showdan."performer_type",'Isabella','Martinez','Группа Martinez Band','https://randomuser.me/api/portraits/men/90.jpg','Группа Martinez Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1990-07-22',15,19101,19,308.34,4.7,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{10}','{10}','{12,13,15}','{2,3,7,8,10}','{"repertoire": ["Covers"], "members_count": 3, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000016'::uuid,'musical_collective'::showdan."performer_type",'Amelia','Martin','Группа Martin Band','https://randomuser.me/api/portraits/men/14.jpg','Группа Martin Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1987-08-20',15,12011,12,275.58,4.9,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{1,4,9}','{4}','{11,12}','{1,2,7,10}','{"repertoire": ["Covers"], "members_count": 3, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000022'::uuid,'musical_collective'::showdan."performer_type",'Oliver','Young','Группа Young Band','https://randomuser.me/api/portraits/men/52.jpg','Группа Young Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1976-04-17',19,58143,58,530.58,5.0,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{4,9}','{4,9}','{11,15}','{1,2,3,7,10}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000028'::uuid,'musical_collective'::showdan."performer_type",'Olivia','Harris','Группа Harris Band','https://randomuser.me/api/portraits/women/27.jpg','Группа Harris Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1991-10-01',12,47771,47,722.12,4.7,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{1}','{1}','{12}','{1,3,7,10}','{"repertoire": ["Covers"], "members_count": 6, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000034'::uuid,'musical_collective'::showdan."performer_type",'Liam','Lee','Группа Lee Band','https://randomuser.me/api/portraits/men/95.jpg','Группа Lee Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1992-03-25',8,8321,8,619.77,4.0,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{8,10}','{10}','{12}','{2,3,8}','{"repertoire": ["Covers"], "members_count": 6, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000040'::uuid,'musical_collective'::showdan."performer_type",'Charlotte','Perez','Группа Perez Band','https://randomuser.me/api/portraits/men/6.jpg','Группа Perez Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1977-10-11',14,98683,98,327.76,4.6,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{1,4}','{4}','{11,15}','{1,2,3,7}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000046'::uuid,'musical_collective'::showdan."performer_type",'Elijah','Wilson','Группа Wilson Band','https://randomuser.me/api/portraits/men/55.jpg','Группа Wilson Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1989-09-21',6,49093,49,587.02,4.6,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{3,9}','{3,9}','{11}','{1,2,7,8,10}','{"repertoire": ["Covers"], "members_count": 6, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000052'::uuid,'musical_collective'::showdan."performer_type",'Charlotte','Jackson','Группа Jackson Band','https://randomuser.me/api/portraits/women/19.jpg','Группа Jackson Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1999-04-20',8,41695,41,347.58,4.9,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{2,10}','{10}','{12}','{2,3,7,10}','{"repertoire": ["Covers"], "members_count": 5, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000058'::uuid,'musical_collective'::showdan."performer_type",'James','Young','Группа Young Band','https://randomuser.me/api/portraits/men/86.jpg','Группа Young Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1970-07-16',19,1877,1,608.75,5.0,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{7,10}','{10}','{15}','{1,8,10}','{"repertoire": ["Covers"], "members_count": 5, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000064'::uuid,'musical_collective'::showdan."performer_type",'Sam','Jackson','Группа Jackson Band','https://randomuser.me/api/portraits/men/28.jpg','Группа Jackson Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1992-05-26',10,24814,24,554.06,4.5,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{7}','{7}','{9,11,12}','{1,2,3}','{"repertoire": ["Covers"], "members_count": 3, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000070'::uuid,'musical_collective'::showdan."performer_type",'Jordan','Harris','Группа Harris Band','https://randomuser.me/api/portraits/men/44.jpg','Группа Harris Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1987-05-26',9,86046,86,430.41,4.1,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{1,6,9}','{1,6,9}','{12}','{1,3,8,10}','{"repertoire": ["Covers"], "members_count": 6, "collective_type": "BAND"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000076'::uuid,'musical_collective'::showdan."performer_type",'Liam','Martin','Группа Martin Band','https://randomuser.me/api/portraits/men/66.jpg','Группа Martin Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1974-11-19',25,68482,68,127.03,4.3,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{2,7}','{2,7}','{9,12}','{1,2,3,7,8}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000082'::uuid,'musical_collective'::showdan."performer_type",'Lucas','Wilson','Группа Wilson Band','https://randomuser.me/api/portraits/women/71.jpg','Группа Wilson Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1983-02-06',27,95187,95,605.90,4.6,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{10}','{10}','{15}','{2,7}','{"repertoire": ["Covers"], "members_count": 3, "collective_type": "BAND"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000088'::uuid,'musical_collective'::showdan."performer_type",'Sophia','Taylor','Группа Taylor Band','https://randomuser.me/api/portraits/women/80.jpg','Группа Taylor Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1984-12-11',21,69187,69,465.03,4.6,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{3,5,7}','{3,5}','{12}','{1,2,3,7,8}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000094'::uuid,'musical_collective'::showdan."performer_type",'Amelia','Jackson','Группа Jackson Band','https://randomuser.me/api/portraits/women/50.jpg','Группа Jackson Band — профессионал в своей сфере. Работает в Toronto.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1972-04-19',26,49053,49,251.23,4.7,'Toronto','SRID=4326;POINT (-79.3832 43.6532)'::public.geometry,'{2,7}','{2}','{12}','{2,7,10}','{"repertoire": ["Covers"], "members_count": 4, "collective_type": "VOCAL_DUET"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000100'::uuid,'musical_collective'::showdan."performer_type",'Sam','Miller','Группа Miller Band','https://randomuser.me/api/portraits/men/65.jpg','Группа Miller Band — профессионал в своей сфере. Работает в London.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1976-03-19',12,8519,8,514.78,4.3,'London','SRID=4326;POINT (-0.1278 51.5074)'::public.geometry,'{2,9}','{9}','{11,13}','{1,2,7}','{"repertoire": ["Covers"], "members_count": 5, "collective_type": "INSTRUMENTAL_GROUP"}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000005'::uuid,'vocal_soloist'::showdan."performer_type",'Evelyn','Rodriguez','Evelyn Rodriguez (Вокал)','https://randomuser.me/api/portraits/women/59.jpg','Evelyn Rodriguez (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1977-03-12',4,93911,93,703.44,4.2,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{2,10}','{2,10}','{8,13,15}','{6,7,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000011'::uuid,'vocal_soloist'::showdan."performer_type",'Alex','Lee','Alex Lee (Вокал)','https://randomuser.me/api/portraits/men/40.jpg','Alex Lee (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1993-09-21',9,64461,64,719.12,4.2,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{5,8,10}','{5,8,10}','{8,12,13}','{7,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Baritone"]}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000017'::uuid,'vocal_soloist'::showdan."performer_type",'Lucas','Young','Lucas Young (Вокал)','https://randomuser.me/api/portraits/women/14.jpg','Lucas Young (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1996-01-22',2,40413,40,603.79,4.5,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{2}','{2}','{11,12,15}','{2,6,7}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Tenor"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000023'::uuid,'vocal_soloist'::showdan."performer_type",'Oliver','Lee','Oliver Lee (Вокал)','https://randomuser.me/api/portraits/women/32.jpg','Oliver Lee (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1991-10-14',3,19251,19,600.84,4.4,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{1,5,7}','{1,5,7}','{8,12}','{7,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Tenor"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000029'::uuid,'vocal_soloist'::showdan."performer_type",'Logan','Jackson','Logan Jackson (Вокал)','https://randomuser.me/api/portraits/men/0.jpg','Logan Jackson (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1975-09-01',23,78545,78,115.01,5.0,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{3,6,10}','{3,6,10}','{11}','{3,6,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Tenor"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000035'::uuid,'vocal_soloist'::showdan."performer_type",'Elijah','Martinez','Elijah Martinez (Вокал)','https://randomuser.me/api/portraits/men/33.jpg','Elijah Martinez (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1970-05-03',29,1642,1,453.76,4.1,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{2,3}','{2}','{15}','{2,3,6,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Tenor"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000041'::uuid,'vocal_soloist'::showdan."performer_type",'Mateo','Brown','Mateo Brown (Вокал)','https://randomuser.me/api/portraits/men/76.jpg','Mateo Brown (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1972-03-16',15,47727,47,631.13,4.5,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{9}','{9}','{8,11,15}','{2,3,7,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Baritone"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000047'::uuid,'vocal_soloist'::showdan."performer_type",'Ethan','Thomas','Ethan Thomas (Вокал)','https://randomuser.me/api/portraits/women/55.jpg','Ethan Thomas (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1998-07-26',7,11623,11,291.14,4.2,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{3,5}','{3,5}','{13}','{3,6,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000053'::uuid,'vocal_soloist'::showdan."performer_type",'Taylor','Moore','Taylor Moore (Вокал)','https://randomuser.me/api/portraits/men/70.jpg','Taylor Moore (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1970-06-27',39,28541,28,147.18,4.3,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{2,9}','{9}','{15}','{2,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Tenor"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000059'::uuid,'vocal_soloist'::showdan."performer_type",'Amelia','Johnson','Amelia Johnson (Вокал)','https://randomuser.me/api/portraits/women/20.jpg','Amelia Johnson (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1982-04-25',3,92205,92,697.33,5.0,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{5}','{5}','{11,13}','{1,2,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000065'::uuid,'vocal_soloist'::showdan."performer_type",'Jordan','Jackson','Jordan Jackson (Вокал)','https://randomuser.me/api/portraits/women/95.jpg','Jordan Jackson (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1978-11-20',24,71003,71,679.20,4.9,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{3}','{3}','{8,15}','{2,8}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000071'::uuid,'vocal_soloist'::showdan."performer_type",'Sam','Clark','Sam Clark (Вокал)','https://randomuser.me/api/portraits/men/26.jpg','Sam Clark (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1981-08-09',9,85470,85,537.89,4.3,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{5,9}','{5,9}','{15}','{1,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Baritone"]}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000077'::uuid,'vocal_soloist'::showdan."performer_type",'Amelia','Davis','Amelia Davis (Вокал)','https://randomuser.me/api/portraits/women/47.jpg','Amelia Davis (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2005-03-26',4,100915,100,570.90,4.5,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{3,6,9}','{3,6,9}','{8,13}','{2,3,7,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000083'::uuid,'vocal_soloist'::showdan."performer_type",'Taylor','Rodriguez','Taylor Rodriguez (Вокал)','https://randomuser.me/api/portraits/men/67.jpg','Taylor Rodriguez (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1971-09-10',18,97363,97,221.73,4.8,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{8}','{8}','{8}','{2,7}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000089'::uuid,'vocal_soloist'::showdan."performer_type",'Emily','Wilson','Emily Wilson (Вокал)','https://randomuser.me/api/portraits/men/16.jpg','Emily Wilson (Вокал) — профессионал в своей сфере. Работает в Manchester.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1986-03-14',9,79510,79,475.61,4.1,'Manchester','SRID=4326;POINT (-2.2426 53.4808)'::public.geometry,'{1,7}','{1,7}','{13,15}','{2,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Baritone"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000095'::uuid,'vocal_soloist'::showdan."performer_type",'Jordan','Brown','Jordan Brown (Вокал)','https://randomuser.me/api/portraits/women/0.jpg','Jordan Brown (Вокал) — профессионал в своей сфере. Работает в Sydney.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1973-07-23',13,65717,65,402.47,4.7,'Sydney','SRID=4326;POINT (151.2093 -33.8688)'::public.geometry,'{4,8}','{8}','{11,12,13}','{1,3,6,8,10}','{"repertoire": ["Pop", "Soul"], "voice_types": ["Soprano"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000006'::uuid,'comic_standup'::showdan."performer_type",'Sofia','Thomas','Sofia (Stand Up)','https://randomuser.me/api/portraits/men/83.jpg','Sofia (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2001-09-04',4,37679,37,520.90,4.6,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{5}','{5}','{2,3,6}','{2,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000012'::uuid,'comic_standup'::showdan."performer_type",'Liam','Taylor','Liam (Stand Up)','https://randomuser.me/api/portraits/men/48.jpg','Liam (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1985-05-10',16,37101,37,209.90,4.9,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{5,7}','{7}','{3}','{7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000018'::uuid,'comic_standup'::showdan."performer_type",'Elijah','White','Elijah (Stand Up)','https://randomuser.me/api/portraits/women/89.jpg','Elijah (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2001-08-12',2,75139,75,314.63,4.1,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{7}','{7}','{3,6}','{2,3,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000024'::uuid,'comic_standup'::showdan."performer_type",'Alex','Davis','Alex (Stand Up)','https://randomuser.me/api/portraits/men/7.jpg','Alex (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1984-07-03',17,90014,90,521.92,4.7,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{1,8,9}','{1,8,9}','{3,6}','{2,3,7,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000030'::uuid,'comic_standup'::showdan."performer_type",'Mateo','Clark','Mateo (Stand Up)','https://randomuser.me/api/portraits/women/62.jpg','Mateo (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2003-07-13',6,24565,24,131.30,4.4,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{1,5}','{5}','{2}','{2,7,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000036'::uuid,'comic_standup'::showdan."performer_type",'Taylor','Anderson','Taylor (Stand Up)','https://randomuser.me/api/portraits/women/97.jpg','Taylor (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1989-07-28',5,26121,26,783.09,4.7,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{7,9,10}','{9,10}','{6}','{2,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03');
INSERT INTO showdan.performers (id,"type",first_name,last_name,stage_name,photo_url,about,description,birth_date,experience_years,xp_points,current_level,hourly_rate,rating,current_city_name,location_point,comm_language_ids,perf_language_ids,genre_ids,event_category_ids,specific_attributes,created_at) VALUES
	 ('00000000-0000-4000-8000-000000000042'::uuid,'comic_standup'::showdan."performer_type",'Emma','Harris','Emma (Stand Up)','https://randomuser.me/api/portraits/women/67.jpg','Emma (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1997-02-20',3,49383,49,354.19,4.2,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{2,6,8}','{2}','{2,3,6}','{2,3}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000048'::uuid,'comic_standup'::showdan."performer_type",'Mateo','Thomas','Mateo (Stand Up)','https://randomuser.me/api/portraits/women/64.jpg','Mateo (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1989-12-25',7,50423,50,308.52,4.8,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{2,3,4}','{2,4}','{6}','{2,3,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000054'::uuid,'comic_standup'::showdan."performer_type",'Alex','Johnson','Alex (Stand Up)','https://randomuser.me/api/portraits/women/61.jpg','Alex (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1991-03-01',14,38777,38,356.85,4.6,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{3,8,10}','{3,8,10}','{2,3,6}','{2,3,7,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000060'::uuid,'comic_standup'::showdan."performer_type",'Mason','Jones','Mason (Stand Up)','https://randomuser.me/api/portraits/women/66.jpg','Mason (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1984-07-23',21,17047,17,631.73,4.2,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{3,8,10}','{3,8,10}','{2,3}','{2,3,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000066'::uuid,'comic_standup'::showdan."performer_type",'Mateo','Jackson','Mateo (Stand Up)','https://randomuser.me/api/portraits/men/56.jpg','Mateo (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1978-11-20',10,51804,51,746.79,4.5,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{4,5,10}','{4,5}','{6}','{2,3,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000072'::uuid,'comic_standup'::showdan."performer_type",'Isabella','Jones','Isabella (Stand Up)','https://randomuser.me/api/portraits/women/60.jpg','Isabella (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1977-03-13',8,83708,83,478.03,4.9,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{4}','{4}','{2,6}','{2,3,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000078'::uuid,'comic_standup'::showdan."performer_type",'Evelyn','Jackson','Evelyn (Stand Up)','https://randomuser.me/api/portraits/women/74.jpg','Evelyn (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1972-01-08',24,96476,96,721.79,4.0,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{1,10}','{1,10}','{2,3}','{3,7,8}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000084'::uuid,'comic_standup'::showdan."performer_type",'Harper','Garcia','Harper (Stand Up)','https://randomuser.me/api/portraits/women/72.jpg','Harper (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1981-03-16',18,63303,63,180.07,4.8,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{1,8,9}','{1,8}','{2,3}','{3,7,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000090'::uuid,'comic_standup'::showdan."performer_type",'Emma','Brown','Emma (Stand Up)','https://randomuser.me/api/portraits/women/77.jpg','Emma (Stand Up) — профессионал в своей сфере. Работает в Paris.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','1982-02-17',19,20345,20,131.88,4.2,'Paris','SRID=4326;POINT (2.3522 48.8566)'::public.geometry,'{5}','{5}','{6}','{2,3,8,10}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03'),
	 ('00000000-0000-4000-8000-000000000096'::uuid,'comic_standup'::showdan."performer_type",'Emma','Harris','Emma (Stand Up)','https://randomuser.me/api/portraits/women/41.jpg','Emma (Stand Up) — профессионал в своей сфере. Работает в Melbourne.','Обновленный профиль с релевантными жанрами и форматами мероприятий.','2004-07-03',1,98734,98,696.45,4.6,'Melbourne','SRID=4326;POINT (144.9631 -37.8136)'::public.geometry,'{3,7,9}','{3}','{2,3}','{2,3,7,8}','{"censorship_rules": ["Без политики", "Без мата"]}','2026-04-20 18:24:19.16296+03');
