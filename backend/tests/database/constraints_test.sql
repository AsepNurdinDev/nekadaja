-- Uji perilaku constraint skema Nekadaja. Dijalankan dalam satu transaksi lalu di-rollback.
\set ON_ERROR_STOP 0
BEGIN;

CREATE TEMP TABLE results (n serial, label text, expect text, got text, pass boolean);
CREATE TEMP TABLE ids (name text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());

CREATE FUNCTION pg_temp.i(p text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid;
BEGIN
  SELECT id INTO r FROM ids WHERE name = p;
  IF r IS NULL THEN INSERT INTO ids(name) VALUES (p) RETURNING id INTO r; END IF;
  RETURN r;
END $$;

-- Harus berhasil
CREATE FUNCTION pg_temp.ok(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO results(label, expect, got, pass) VALUES (p_label, 'ok', 'ok', true);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO results(label, expect, got, pass) VALUES (p_label, 'ok', SQLSTATE || ' ' || SQLERRM, false);
  END;
END $$;

-- Harus ditolak dengan SQLSTATE tertentu (23505 unique, 23514 check, 23503 fk)
CREATE FUNCTION pg_temp.bad(p_label text, p_state text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO results(label, expect, got, pass) VALUES (p_label, p_state, 'DITERIMA (seharusnya ditolak)', false);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO results(label, expect, got, pass) VALUES (p_label, p_state, SQLSTATE, SQLSTATE = p_state);
  END;
END $$;

-- ---------- fixture ----------
SELECT pg_temp.ok('fixture: users', format($f$
  INSERT INTO users(id,name,email) VALUES
   ('%s','Author','author@x.id'),('%s','Student A','a@x.id'),('%s','Student B','b@x.id'),('%s','Temp','temp@x.id')$f$,
   pg_temp.i('author'), pg_temp.i('ua'), pg_temp.i('ub'), pg_temp.i('utemp')));
SELECT pg_temp.ok('fixture: products', format($f$
  INSERT INTO products(id,product_type,title,slug,pricing_type,price_amount,minimum_amount,status,published_at,created_by) VALUES
   ('%s','course','C1','c1','fixed',100000,0,'published',now(),'%s'),
   ('%s','source_code','S1','s1','pwyw',50000,10000,'published',now(),'%s'),
   ('%s','course','C2 free','c2','free',0,0,'draft',NULL,'%s')$f$,
   pg_temp.i('p_course'), pg_temp.i('author'), pg_temp.i('p_src'), pg_temp.i('author'), pg_temp.i('p_free'), pg_temp.i('author')));
SELECT pg_temp.ok('fixture: course detail', format(
  $f$INSERT INTO courses(id,product_id) VALUES ('%s','%s')$f$, pg_temp.i('course'), pg_temp.i('p_course')));
SELECT pg_temp.ok('fixture: source detail', format(
  $f$INSERT INTO source_code_details(id,product_id) VALUES ('%s','%s')$f$, pg_temp.i('scd'), pg_temp.i('p_src')));

-- ---------- identity ----------
SELECT pg_temp.bad('email huruf besar ditolak', '23514',
  $$INSERT INTO users(name,email) VALUES ('X','Upper@X.id')$$);
SELECT pg_temp.bad('email duplikat ditolak', '23505',
  $$INSERT INTO users(name,email) VALUES ('X','a@x.id')$$);
SELECT pg_temp.bad('status user tidak valid ditolak', '23514',
  $$INSERT INTO users(name,email,status) VALUES ('X','z@x.id','banned')$$);
SELECT pg_temp.bad('oauth provider+uid duplikat ditolak', '23505', format($f$
  INSERT INTO user_oauth_accounts(user_id,provider,provider_user_id) VALUES ('%s','google','g1'),('%s','google','g1')$f$,
  pg_temp.i('ua'), pg_temp.i('ub')));
SELECT pg_temp.ok('seed role = 3', $q$DO $x$ BEGIN IF (SELECT count(*) FROM roles WHERE name IN ('admin','author','student')) <> 3 THEN RAISE EXCEPTION 'seed hilang'; END IF; END $x$$q$);

-- ---------- products: aturan harga ----------
SELECT pg_temp.bad('free dengan harga ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,price_amount,created_by) VALUES ('course','t','t1','free',1000,'%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('fixed harga 0 ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,price_amount,created_by) VALUES ('course','t','t2','fixed',0,'%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('fixed dengan minimum ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,price_amount,minimum_amount,created_by) VALUES ('course','t','t3','fixed',1000,500,'%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('pwyw tanpa minimum ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,created_by) VALUES ('course','t','t4','pwyw','%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('pwyw saran < minimum ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,price_amount,minimum_amount,created_by) VALUES ('course','t','t5','pwyw',5000,10000,'%s')$f$, pg_temp.i('author')));
SELECT pg_temp.ok('pwyw tanpa saran (price 0) diterima', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,minimum_amount,created_by) VALUES ('course','t','t6','pwyw',10000,'%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('published tanpa published_at ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,status,created_by) VALUES ('course','t','t7','free','published','%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('slug duplikat ditolak', '23505', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,created_by) VALUES ('course','t','c1','free','%s')$f$, pg_temp.i('author')));
SELECT pg_temp.bad('harga negatif ditolak', '23514', format($f$
  INSERT INTO products(product_type,title,slug,pricing_type,price_amount,created_by) VALUES ('course','t','t8','fixed',-5,'%s')$f$, pg_temp.i('author')));

-- ---------- FK komposit product_type ----------
SELECT pg_temp.bad('detail course ke produk source_code ditolak', '23503', format($f$
  INSERT INTO courses(product_id) VALUES ('%s')$f$, pg_temp.i('p_src')));
SELECT pg_temp.bad('detail source_code ke produk course ditolak', '23503', format($f$
  INSERT INTO source_code_details(product_id) VALUES ('%s')$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('detail course kedua untuk produk sama ditolak', '23505', format($f$
  INSERT INTO courses(product_id) VALUES ('%s')$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('ubah product_type setelah ada detail ditolak', '23503', format($f$
  UPDATE products SET product_type='source_code' WHERE id='%s'$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('courses.product_type selain course ditolak', '23514', format($f$
  INSERT INTO courses(product_id,product_type) VALUES ('%s','source_code')$f$, pg_temp.i('p_free')));
SELECT pg_temp.ok('detail course untuk produk course diterima', format($f$
  INSERT INTO courses(product_id) VALUES ('%s')$f$, pg_temp.i('p_free')));

-- ---------- course: position deferrable ----------
SELECT pg_temp.ok('section A,B', format($f$
  INSERT INTO course_sections(id,course_id,title,position) VALUES ('%s','%s','A',1),('%s','%s','B',2)$f$,
  pg_temp.i('secA'), pg_temp.i('course'), pg_temp.i('secB'), pg_temp.i('course')));
SELECT pg_temp.bad('position section duplikat ditolak (immediate)', '23505', format($f$
  DO $x$ BEGIN
    INSERT INTO course_sections(course_id,title,position) VALUES ('%s','C',1);
    SET CONSTRAINTS ALL IMMEDIATE;
  END $x$$f$, pg_temp.i('course')));
SELECT pg_temp.ok('tukar posisi section dalam satu transaksi (deferred)', format($f$
  DO $x$ BEGIN
    UPDATE course_sections SET position = 3 - position WHERE course_id='%s';
    SET CONSTRAINTS ALL IMMEDIATE;
  END $x$$f$, pg_temp.i('course')));
SELECT pg_temp.ok('lesson text', format($f$
  INSERT INTO lessons(id,section_id,title,slug,lesson_type,position) VALUES ('%s','%s','L1','l1','text',1)$f$,
  pg_temp.i('lesson'), pg_temp.i('secA')));
SELECT pg_temp.bad('lesson slug duplikat per section ditolak', '23505', format($f$
  INSERT INTO lessons(section_id,title,slug,lesson_type,position) VALUES ('%s','L1b','l1','text',2)$f$, pg_temp.i('secA')));
SELECT pg_temp.bad('lesson video published tanpa video_url ditolak', '23514', format($f$
  INSERT INTO lessons(section_id,title,slug,lesson_type,position,status) VALUES ('%s','V','v1','video',5,'published')$f$, pg_temp.i('secA')));
SELECT pg_temp.ok('lesson video draft tanpa video_url diterima', format($f$
  INSERT INTO lessons(section_id,title,slug,lesson_type,position,status) VALUES ('%s','V','v2','video',6,'draft')$f$, pg_temp.i('secA')));
SELECT pg_temp.bad('lesson_type tidak valid ditolak', '23514', format($f$
  INSERT INTO lessons(section_id,title,slug,lesson_type,position) VALUES ('%s','P','p1','pdf',7)$f$, pg_temp.i('secA')));

-- ---------- examination ----------
SELECT pg_temp.ok('exam + 2 pertanyaan + opsi', format($f$
  DO $x$ BEGIN
    INSERT INTO exams(id,course_id,title,duration_minutes,passing_score) VALUES ('%1$s','%2$s','E',30,70);
    INSERT INTO exam_questions(id,exam_id,question_text,question_type,position) VALUES
      ('%3$s','%1$s','Q1','single_choice',1),('%4$s','%1$s','Q2','multiple_choice',2);
    INSERT INTO exam_answer_options(id,question_id,option_text,is_correct,position) VALUES
      ('%5$s','%3$s','a',true,1),('%6$s','%3$s','b',false,2),
      ('%7$s','%4$s','x',true,1),('%8$s','%4$s','y',true,2),('%9$s','%4$s','z',false,3);
  END $x$$f$,
  pg_temp.i('exam'), pg_temp.i('course'), pg_temp.i('q1'), pg_temp.i('q2'),
  pg_temp.i('q1a'), pg_temp.i('q1b'), pg_temp.i('q2x'), pg_temp.i('q2y'), pg_temp.i('q2z')));
SELECT pg_temp.bad('passing_score > 100 ditolak', '23514', format($f$
  INSERT INTO exams(course_id,title,duration_minutes,passing_score) VALUES ('%s','E2',30,101)$f$, pg_temp.i('course')));
SELECT pg_temp.bad('max_attempts 0 ditolak', '23514', format($f$
  INSERT INTO exams(course_id,title,duration_minutes,passing_score,max_attempts) VALUES ('%s','E3',30,70,0)$f$, pg_temp.i('course')));
SELECT pg_temp.bad('opsi tanpa teks/gambar ditolak', '23514', format($f$
  INSERT INTO exam_answer_options(question_id,position) VALUES ('%s',9)$f$, pg_temp.i('q1')));
SELECT pg_temp.ok('attempt #1 in_progress', format($f$
  INSERT INTO exam_attempts(id,exam_id,user_id,attempt_number,started_at) VALUES ('%s','%s','%s',1,now())$f$,
  pg_temp.i('att1'), pg_temp.i('exam'), pg_temp.i('ua')));
SELECT pg_temp.bad('attempt in_progress kedua ditolak', '23505', format($f$
  INSERT INTO exam_attempts(exam_id,user_id,attempt_number,started_at) VALUES ('%s','%s',2,now())$f$,
  pg_temp.i('exam'), pg_temp.i('ua')));
SELECT pg_temp.bad('attempt_number duplikat ditolak', '23505', format($f$
  INSERT INTO exam_attempts(exam_id,user_id,attempt_number,started_at,status) VALUES ('%s','%s',1,now(),'expired')$f$,
  pg_temp.i('exam'), pg_temp.i('ua')));
SELECT pg_temp.ok('attempt selesai lalu attempt baru diterima', format($f$
  DO $x$ BEGIN
    UPDATE exam_attempts SET status='graded', submitted_at=now(), score=80, is_passed=true WHERE id='%1$s';
    INSERT INTO exam_attempts(exam_id,user_id,attempt_number,started_at) VALUES ('%2$s','%3$s',2,now());
  END $x$$f$, pg_temp.i('att1'), pg_temp.i('exam'), pg_temp.i('ua')));
SELECT pg_temp.bad('submitted_at < started_at ditolak', '23514', format($f$
  UPDATE exam_attempts SET submitted_at = started_at - interval '1 hour' WHERE id='%s'$f$, pg_temp.i('att1')));
SELECT pg_temp.bad('score > 100 ditolak', '23514', format($f$
  UPDATE exam_attempts SET score = 150 WHERE id='%s'$f$, pg_temp.i('att1')));
SELECT pg_temp.ok('jawaban single_choice dengan opsi milik pertanyaan', format($f$
  INSERT INTO exam_answers(id,attempt_id,question_id,selected_option_id,is_correct,earned_points) VALUES ('%s','%s','%s','%s',true,1)$f$,
  pg_temp.i('ans1'), pg_temp.i('att1'), pg_temp.i('q1'), pg_temp.i('q1a')));
SELECT pg_temp.bad('jawaban dengan opsi dari pertanyaan lain ditolak', '23503', format($f$
  INSERT INTO exam_answers(attempt_id,question_id,selected_option_id) VALUES ('%s','%s','%s')$f$,
  pg_temp.i('att1'), pg_temp.i('q2'), pg_temp.i('q1a')));
SELECT pg_temp.bad('jawaban ganda untuk pertanyaan sama ditolak', '23505', format($f$
  INSERT INTO exam_answers(attempt_id,question_id) VALUES ('%s','%s')$f$, pg_temp.i('att1'), pg_temp.i('q1')));
SELECT pg_temp.ok('jawaban multiple_choice tanpa selected_option_id', format($f$
  INSERT INTO exam_answers(id,attempt_id,question_id) VALUES ('%s','%s','%s')$f$, pg_temp.i('ans2'), pg_temp.i('att1'), pg_temp.i('q2')));
SELECT pg_temp.ok('multi-select opsi milik pertanyaan', format($f$
  INSERT INTO exam_answer_options_selected(answer_id,question_id,option_id) VALUES ('%1$s','%2$s','%3$s'),('%1$s','%2$s','%4$s')$f$,
  pg_temp.i('ans2'), pg_temp.i('q2'), pg_temp.i('q2x'), pg_temp.i('q2y')));
SELECT pg_temp.bad('multi-select opsi dari pertanyaan lain ditolak', '23503', format($f$
  INSERT INTO exam_answer_options_selected(answer_id,question_id,option_id) VALUES ('%s','%s','%s')$f$,
  pg_temp.i('ans2'), pg_temp.i('q2'), pg_temp.i('q1b')));
SELECT pg_temp.bad('multi-select dengan question_id tidak cocok jawaban ditolak', '23503', format($f$
  INSERT INTO exam_answer_options_selected(answer_id,question_id,option_id) VALUES ('%s','%s','%s')$f$,
  pg_temp.i('ans2'), pg_temp.i('q1'), pg_temp.i('q1b')));
SELECT pg_temp.bad('hapus pertanyaan yang sudah dijawab ditolak', '23503', format($f$
  DELETE FROM exam_questions WHERE id='%s'$f$, pg_temp.i('q1')));
SELECT pg_temp.bad('hapus exam yang punya attempt ditolak', '23503', format($f$
  DELETE FROM exams WHERE id='%s'$f$, pg_temp.i('exam')));

-- ---------- certificates ----------
SELECT pg_temp.ok('template + sertifikat aktif', format($f$
  DO $x$ BEGIN
    INSERT INTO certificate_templates(id,name,template_file_url) VALUES ('%1$s','T','s3://t');
    INSERT INTO certificates(id,user_id,course_id,template_id,certificate_number,issued_at) VALUES ('%2$s','%3$s','%4$s','%1$s','CERT-1',now());
  END $x$$f$, pg_temp.i('tpl'), pg_temp.i('cert1'), pg_temp.i('ua'), pg_temp.i('course')));
SELECT pg_temp.bad('sertifikat aktif ganda ditolak', '23505', format($f$
  INSERT INTO certificates(user_id,course_id,template_id,certificate_number,issued_at) VALUES ('%s','%s','%s','CERT-2',now())$f$,
  pg_temp.i('ua'), pg_temp.i('course'), pg_temp.i('tpl')));
SELECT pg_temp.bad('nomor sertifikat duplikat ditolak', '23505', format($f$
  INSERT INTO certificates(user_id,course_id,template_id,certificate_number,issued_at) VALUES ('%s','%s','%s','CERT-1',now())$f$,
  pg_temp.i('ub'), pg_temp.i('course'), pg_temp.i('tpl')));
SELECT pg_temp.ok('cabut lalu terbitkan ulang diterima', format($f$
  DO $x$ BEGIN
    UPDATE certificates SET revoked_at = now() WHERE id='%1$s';
    INSERT INTO certificates(user_id,course_id,template_id,certificate_number,issued_at) VALUES ('%2$s','%3$s','%4$s','CERT-3',now());
  END $x$$f$, pg_temp.i('cert1'), pg_temp.i('ua'), pg_temp.i('course'), pg_temp.i('tpl')));

-- ---------- source code ----------
SELECT pg_temp.ok('versi 1.0.0 latest', format($f$
  INSERT INTO source_code_versions(id,source_code_id,version,is_latest,released_at) VALUES ('%s','%s','1.0.0',true,now())$f$,
  pg_temp.i('v1'), pg_temp.i('scd')));
SELECT pg_temp.bad('dua versi latest ditolak', '23505', format($f$
  INSERT INTO source_code_versions(source_code_id,version,is_latest,released_at) VALUES ('%s','1.1.0',true,now())$f$, pg_temp.i('scd')));
SELECT pg_temp.bad('versi duplikat ditolak', '23505', format($f$
  INSERT INTO source_code_versions(source_code_id,version,released_at) VALUES ('%s','1.0.0',now())$f$, pg_temp.i('scd')));
SELECT pg_temp.ok('pindah latest dalam satu transaksi', format($f$
  DO $x$ BEGIN
    UPDATE source_code_versions SET is_latest=false WHERE id='%1$s';
    INSERT INTO source_code_versions(source_code_id,version,is_latest,released_at) VALUES ('%2$s','1.1.0',true,now());
  END $x$$f$, pg_temp.i('v1'), pg_temp.i('scd')));
SELECT pg_temp.ok('file primary + non-primary untuk versi', format($f$
  INSERT INTO product_files(product_id,source_code_version_id,file_name,storage_key,mime_type,file_size,is_primary) VALUES
   ('%1$s','%2$s','a.zip','k/a','application/zip',100,true),('%1$s','%2$s','b.zip','k/b','application/zip',100,false)$f$,
  pg_temp.i('p_src'), pg_temp.i('v1')));
SELECT pg_temp.bad('dua file primary per versi ditolak', '23505', format($f$
  INSERT INTO product_files(product_id,source_code_version_id,file_name,storage_key,mime_type,file_size,is_primary) VALUES ('%s','%s','c.zip','k/c','application/zip',1,true)$f$,
  pg_temp.i('p_src'), pg_temp.i('v1')));
SELECT pg_temp.bad('storage_key duplikat ditolak', '23505', format($f$
  INSERT INTO product_files(product_id,file_name,storage_key,mime_type,file_size) VALUES ('%s','d.pdf','k/a','application/pdf',1)$f$, pg_temp.i('p_course')));
SELECT pg_temp.ok('file course (versi NULL), primary', format($f$
  INSERT INTO product_files(product_id,file_name,storage_key,mime_type,file_size,is_primary) VALUES ('%s','slides.pdf','k/slides','application/pdf',1,true)$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('dua file primary per course ditolak', '23505', format($f$
  INSERT INTO product_files(product_id,file_name,storage_key,mime_type,file_size,is_primary) VALUES ('%s','s2.pdf','k/s2','application/pdf',1,true)$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('file_size negatif ditolak', '23514', format($f$
  INSERT INTO product_files(product_id,file_name,storage_key,mime_type,file_size) VALUES ('%s','n.pdf','k/n','application/pdf',-1)$f$, pg_temp.i('p_course')));

-- ---------- orders ----------
SELECT pg_temp.ok('order pending + item', format($f$
  DO $x$ BEGIN
    INSERT INTO orders(id,order_number,user_id,subtotal_amount,total_amount) VALUES ('%1$s','ORD-1','%2$s',100000,100000);
    INSERT INTO order_items(id,order_id,product_id,product_title,product_type,unit_price,subtotal_amount) VALUES ('%3$s','%1$s','%4$s','C1','course',100000,100000);
  END $x$$f$, pg_temp.i('o1'), pg_temp.i('ua'), pg_temp.i('oi1'), pg_temp.i('p_course')));
SELECT pg_temp.bad('total != subtotal - diskon ditolak', '23514', format($f$
  INSERT INTO orders(order_number,user_id,subtotal_amount,discount_amount,total_amount) VALUES ('ORD-X','%s',100000,10000,100000)$f$, pg_temp.i('ua')));
SELECT pg_temp.bad('diskon > subtotal ditolak', '23514', format($f$
  INSERT INTO orders(order_number,user_id,subtotal_amount,discount_amount,total_amount) VALUES ('ORD-Y','%s',1000,2000,-1000)$f$, pg_temp.i('ua')));
SELECT pg_temp.bad('order paid tanpa paid_at ditolak', '23514', format($f$
  INSERT INTO orders(order_number,user_id,subtotal_amount,total_amount,status) VALUES ('ORD-Z','%s',0,0,'paid')$f$, pg_temp.i('ua')));
SELECT pg_temp.bad('order_number duplikat ditolak', '23505', format($f$
  INSERT INTO orders(order_number,user_id,subtotal_amount,total_amount) VALUES ('ORD-1','%s',0,0)$f$, pg_temp.i('ua')));
SELECT pg_temp.bad('item kedua untuk order sama ditolak', '23505', format($f$
  INSERT INTO order_items(order_id,product_id,product_title,product_type,unit_price,subtotal_amount) VALUES ('%s','%s','S1','source_code',0,0)$f$, pg_temp.i('o1'), pg_temp.i('p_src')));
SELECT pg_temp.bad('quantity 2 ditolak', '23514', format($f$
  DO $x$ BEGIN
    INSERT INTO orders(id,order_number,user_id,subtotal_amount,total_amount) VALUES ('%1$s','ORD-Q','%2$s',200,200);
    INSERT INTO order_items(order_id,product_id,product_title,product_type,unit_price,quantity,subtotal_amount)
      VALUES ('%1$s','%3$s','S1','source_code',100,2,200);
  END $x$$f$, pg_temp.i('oq'), pg_temp.i('ua'), pg_temp.i('p_src')));
SELECT pg_temp.bad('subtotal item != unit_price * quantity ditolak', '23514', format($f$
  DO $x$ BEGIN
    INSERT INTO orders(id,order_number,user_id,subtotal_amount,total_amount) VALUES ('%1$s','ORD-Q2','%2$s',999,999);
    INSERT INTO order_items(order_id,product_id,product_title,product_type,unit_price,subtotal_amount)
      VALUES ('%1$s','%3$s','S1','source_code',100,999);
  END $x$$f$, pg_temp.i('oq2'), pg_temp.i('ua'), pg_temp.i('p_src')));
SELECT pg_temp.ok('order gratis langsung paid, total 0, item unit_price 0', format($f$
  DO $x$ BEGIN
    INSERT INTO orders(id,order_number,user_id,subtotal_amount,total_amount,status,paid_at) VALUES ('%1$s','ORD-FREE','%2$s',0,0,'paid',now());
    INSERT INTO order_items(id,order_id,product_id,product_title,product_type,unit_price,subtotal_amount) VALUES ('%3$s','%1$s','%4$s','C2 free','course',0,0);
  END $x$$f$, pg_temp.i('ofree'), pg_temp.i('ub'), pg_temp.i('oifree'), pg_temp.i('p_free')));

-- ---------- payments ----------
SELECT pg_temp.ok('payment #1 failed', format($f$
  INSERT INTO payments(id,order_id,provider,provider_reference,amount,status) VALUES ('%s','%s','midtrans','ref-1',100000,'failed')$f$,
  pg_temp.i('pay1'), pg_temp.i('o1')));
SELECT pg_temp.ok('payment #2 paid (percobaan ulang)', format($f$
  INSERT INTO payments(id,order_id,provider,provider_reference,amount,status,paid_at) VALUES ('%s','%s','midtrans','ref-2',100000,'paid',now())$f$,
  pg_temp.i('pay2'), pg_temp.i('o1')));
SELECT pg_temp.bad('payment berhasil kedua untuk order sama ditolak', '23505', format($f$
  INSERT INTO payments(order_id,provider,provider_reference,amount,status,paid_at) VALUES ('%s','xendit','x-1',100000,'paid',now())$f$, pg_temp.i('o1')));
SELECT pg_temp.bad('payment amount 0 ditolak', '23514', format($f$
  INSERT INTO payments(order_id,provider,amount) VALUES ('%s','midtrans',0)$f$, pg_temp.i('o1')));
SELECT pg_temp.bad('payment paid tanpa paid_at ditolak', '23514', format($f$
  INSERT INTO payments(order_id,provider,amount,status) VALUES ('%s','midtrans',1,'paid')$f$, pg_temp.i('ofree')));
SELECT pg_temp.bad('provider_reference duplikat per provider ditolak', '23505', format($f$
  INSERT INTO payments(order_id,provider,provider_reference,amount) VALUES ('%s','midtrans','ref-1',1)$f$, pg_temp.i('o1')));
SELECT pg_temp.ok('provider_reference sama di provider lain diterima', format($f$
  INSERT INTO payments(order_id,provider,provider_reference,amount) VALUES ('%s','xendit','ref-1',1)$f$, pg_temp.i('o1')));
SELECT pg_temp.ok('payment_event pertama', format($f$
  INSERT INTO payment_events(payment_id,provider,provider_event_id,event_type,payload) VALUES ('%s','midtrans','evt-1','settlement','{}')$f$, pg_temp.i('pay2')));
SELECT pg_temp.bad('webhook payment duplikat (idempotensi) ditolak', '23505', format($f$
  INSERT INTO payment_events(payment_id,provider,provider_event_id,event_type,payload) VALUES ('%s','midtrans','evt-1','settlement','{}')$f$, pg_temp.i('pay2')));
SELECT pg_temp.ok('event ID sama di provider lain diterima', format($f$
  INSERT INTO payment_events(payment_id,provider,provider_event_id,event_type,payload) VALUES ('%s','xendit','evt-1','paid','{}')$f$, pg_temp.i('pay2')));
SELECT pg_temp.ok('event tanpa event ID boleh berulang', format($f$
  INSERT INTO payment_events(payment_id,provider,event_type,payload) VALUES ('%1$s','midtrans','x','{}'),('%1$s','midtrans','x','{}')$f$, pg_temp.i('pay2')));

-- ---------- refunds ----------
SELECT pg_temp.ok('refund valid', format($f$
  INSERT INTO refunds(id,payment_id,order_id,user_id,refund_number,amount) VALUES ('%s','%s','%s','%s','RF-1',50000)$f$,
  pg_temp.i('rf1'), pg_temp.i('pay2'), pg_temp.i('o1'), pg_temp.i('ua')));
SELECT pg_temp.bad('refund order_id tidak cocok dengan payment ditolak', '23503', format($f$
  INSERT INTO refunds(payment_id,order_id,user_id,refund_number,amount) VALUES ('%s','%s','%s','RF-2',1000)$f$,
  pg_temp.i('pay2'), pg_temp.i('ofree'), pg_temp.i('ub')));
SELECT pg_temp.bad('refund user_id bukan pemilik order ditolak', '23503', format($f$
  INSERT INTO refunds(payment_id,order_id,user_id,refund_number,amount) VALUES ('%s','%s','%s','RF-3',1000)$f$,
  pg_temp.i('pay2'), pg_temp.i('o1'), pg_temp.i('ub')));
SELECT pg_temp.bad('refund amount 0 ditolak', '23514', format($f$
  INSERT INTO refunds(payment_id,order_id,user_id,refund_number,amount) VALUES ('%s','%s','%s','RF-4',0)$f$,
  pg_temp.i('pay2'), pg_temp.i('o1'), pg_temp.i('ua')));
SELECT pg_temp.bad('refund_number duplikat ditolak', '23505', format($f$
  INSERT INTO refunds(payment_id,order_id,user_id,refund_number,amount) VALUES ('%s','%s','%s','RF-1',1000)$f$,
  pg_temp.i('pay2'), pg_temp.i('o1'), pg_temp.i('ua')));
SELECT pg_temp.ok('refund_event pertama', format($f$
  INSERT INTO refund_events(refund_id,provider_event_id,event_type) VALUES ('%s','re-1','processed')$f$, pg_temp.i('rf1')));
SELECT pg_temp.bad('webhook refund duplikat ditolak', '23505', format($f$
  INSERT INTO refund_events(refund_id,provider_event_id,event_type) VALUES ('%s','re-1','processed')$f$, pg_temp.i('rf1')));

-- ---------- entitlements ----------
SELECT pg_temp.ok('entitlement dari order item', format($f$
  INSERT INTO entitlements(id,user_id,product_id,order_item_id,granted_at) VALUES ('%s','%s','%s','%s',now())$f$,
  pg_temp.i('en1'), pg_temp.i('ua'), pg_temp.i('p_course'), pg_temp.i('oi1')));
SELECT pg_temp.bad('entitlement dengan produk berbeda dari order item ditolak', '23503', format($f$
  INSERT INTO entitlements(user_id,product_id,order_item_id,granted_at) VALUES ('%s','%s','%s',now())$f$,
  pg_temp.i('ub'), pg_temp.i('p_src'), pg_temp.i('oifree')));
SELECT pg_temp.bad('satu order item dua entitlement ditolak', '23505', format($f$
  INSERT INTO entitlements(user_id,product_id,order_item_id,granted_at) VALUES ('%s','%s','%s',now())$f$,
  pg_temp.i('ua'), pg_temp.i('p_course'), pg_temp.i('oi1')));
SELECT pg_temp.bad('revoked_reason tanpa revoked_at ditolak', '23514', format($f$
  UPDATE entitlements SET revoked_reason='x' WHERE id='%s'$f$, pg_temp.i('en1')));
-- entitlement aktif ganda: butuh order item kedua untuk produk yang sama + user yang sama
SELECT pg_temp.ok('order #2 produk sama (user A) disiapkan', format($f$
  DO $x$ BEGIN
    INSERT INTO orders(id,order_number,user_id,subtotal_amount,total_amount,status,paid_at) VALUES ('%1$s','ORD-2','%2$s',100000,100000,'paid',now());
    INSERT INTO order_items(id,order_id,product_id,product_title,product_type,unit_price,subtotal_amount) VALUES ('%3$s','%1$s','%4$s','C1','course',100000,100000);
  END $x$$f$, pg_temp.i('o2'), pg_temp.i('ua'), pg_temp.i('oi2'), pg_temp.i('p_course')));
SELECT pg_temp.bad('entitlement aktif ganda (user+produk) ditolak', '23505', format($f$
  INSERT INTO entitlements(user_id,product_id,order_item_id,granted_at) VALUES ('%s','%s','%s',now())$f$,
  pg_temp.i('ua'), pg_temp.i('p_course'), pg_temp.i('oi2')));
SELECT pg_temp.ok('cabut entitlement lalu beli ulang diterima', format($f$
  DO $x$ BEGIN
    UPDATE entitlements SET revoked_at=now(), revoked_reason='refund' WHERE id='%1$s';
    INSERT INTO entitlements(user_id,product_id,order_item_id,granted_at) VALUES ('%2$s','%3$s','%4$s',now());
  END $x$$f$, pg_temp.i('en1'), pg_temp.i('ua'), pg_temp.i('p_course'), pg_temp.i('oi2')));

-- ---------- progress ----------
SELECT pg_temp.ok('lesson_progress', format($f$
  INSERT INTO lesson_progress(user_id,lesson_id,is_completed,completed_at) VALUES ('%s','%s',true,now())$f$, pg_temp.i('ua'), pg_temp.i('lesson')));
SELECT pg_temp.bad('lesson_progress duplikat ditolak', '23505', format($f$
  INSERT INTO lesson_progress(user_id,lesson_id) VALUES ('%s','%s')$f$, pg_temp.i('ua'), pg_temp.i('lesson')));
SELECT pg_temp.bad('is_completed tanpa completed_at ditolak', '23514', format($f$
  INSERT INTO lesson_progress(user_id,lesson_id,is_completed) VALUES ('%s','%s',true)$f$, pg_temp.i('ub'), pg_temp.i('lesson')));
SELECT pg_temp.bad('course_progress completed > total ditolak', '23514', format($f$
  INSERT INTO course_progress(user_id,course_id,completed_lessons,total_lessons) VALUES ('%s','%s',5,3)$f$, pg_temp.i('ua'), pg_temp.i('course')));
SELECT pg_temp.bad('course_progress persentase > 100 ditolak', '23514', format($f$
  INSERT INTO course_progress(user_id,course_id,progress_percentage) VALUES ('%s','%s',101)$f$, pg_temp.i('ua'), pg_temp.i('course')));

-- ---------- referential action ----------
SELECT pg_temp.bad('hapus produk yang pernah dipesan ditolak (RESTRICT)', '23503', format($f$
  DELETE FROM products WHERE id='%s'$f$, pg_temp.i('p_course')));
SELECT pg_temp.bad('hapus user yang punya order ditolak (RESTRICT)', '23503', format($f$
  DELETE FROM users WHERE id='%s'$f$, pg_temp.i('ua')));
SELECT pg_temp.ok('audit_log user + hapus user -> user_id NULL', format($f$
  DO $x$ BEGIN
    INSERT INTO audit_logs(id,user_id,action,ip_address) VALUES ('%1$s','%2$s','login','10.0.0.1');
    DELETE FROM users WHERE id='%2$s';
    IF (SELECT user_id FROM audit_logs WHERE id='%1$s') IS NOT NULL THEN RAISE EXCEPTION 'user_id tidak NULL'; END IF;
  END $x$$f$, pg_temp.i('al1'), pg_temp.i('utemp')));
SELECT pg_temp.ok('hapus user -> token ikut terhapus (CASCADE)', format($f$
  DO $x$ BEGIN
    INSERT INTO users(id,name,email) VALUES ('%1$s','T2','t2@x.id');
    INSERT INTO refresh_tokens(user_id,token_hash,expires_at) VALUES ('%1$s','h1',now()+interval '1 day');
    DELETE FROM users WHERE id='%1$s';
    IF EXISTS (SELECT 1 FROM refresh_tokens WHERE token_hash='h1') THEN RAISE EXCEPTION 'token tidak terhapus'; END IF;
  END $x$$f$, pg_temp.i('ut2')));
SELECT pg_temp.bad('hapus produk gratis yang punya order ditolak (RESTRICT)', '23503', format($f$
  DELETE FROM products WHERE id='%s'$f$, pg_temp.i('p_free')));
SELECT pg_temp.ok('hapus produk draft tanpa order -> course, section, lesson ikut terhapus (CASCADE)', format($f$
  DO $x$ BEGIN
    INSERT INTO products(id,product_type,title,slug,pricing_type,created_by) VALUES ('%1$s','course','D','draft-x','free','%2$s');
    INSERT INTO courses(id,product_id) VALUES ('%3$s','%1$s');
    INSERT INTO course_sections(id,course_id,title,position) VALUES ('%4$s','%3$s','S',1);
    INSERT INTO lessons(section_id,title,slug,lesson_type,position) VALUES ('%4$s','L','l','text',1);
    DELETE FROM products WHERE id='%1$s';
    IF EXISTS (SELECT 1 FROM courses WHERE id='%3$s') OR EXISTS (SELECT 1 FROM course_sections WHERE id='%4$s')
       OR EXISTS (SELECT 1 FROM lessons WHERE section_id='%4$s') THEN RAISE EXCEPTION 'cascade tidak berjalan'; END IF;
  END $x$$f$, pg_temp.i('p_draft'), pg_temp.i('author'), pg_temp.i('c_draft'), pg_temp.i('sec_draft')));

-- ---------- trigger updated_at ----------
SELECT pg_temp.ok('trigger updated_at memperbarui kolom', format($f$
  DO $x$ DECLARE a timestamptz; b timestamptz; BEGIN
    UPDATE users SET updated_at = '2000-01-01' WHERE id='%1$s';
    -- trigger menimpa nilai manual dengan now()
    SELECT updated_at INTO b FROM users WHERE id='%1$s';
    UPDATE users SET name = 'Student A2' WHERE id='%1$s';
    SELECT updated_at INTO a FROM users WHERE id='%1$s';
    IF a < now() - interval '1 minute' THEN RAISE EXCEPTION 'updated_at tidak diperbarui: %%', a; END IF;
  END $x$$f$, pg_temp.i('ua')));

\echo
\echo '=== HASIL ==='
SELECT n, CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END AS hasil, label, expect, got FROM results WHERE NOT pass ORDER BY n;
SELECT count(*) FILTER (WHERE pass) AS lulus, count(*) FILTER (WHERE NOT pass) AS gagal, count(*) AS total FROM results;
ROLLBACK;
