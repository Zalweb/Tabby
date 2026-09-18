-- Google Classroom integration: connection metadata, read-only course data,
-- assignment reminders, and teacher announcements.

CREATE TABLE IF NOT EXISTS classroom_connections (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  google_email    text NOT NULL,
  connected_at    timestamptz NOT NULL DEFAULT now(),
  last_synced_at  timestamptz,
  is_active       boolean NOT NULL DEFAULT true,
  alarm_60m       boolean NOT NULL DEFAULT true,
  alarm_30m       boolean NOT NULL DEFAULT true,
  alarm_10m       boolean NOT NULL DEFAULT true,
  UNIQUE(user_id)
);

CREATE TABLE IF NOT EXISTS classroom_courses (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  google_course_id text NOT NULL,
  name             text NOT NULL,
  section          text,
  color_hex        text NOT NULL DEFAULT '#4CAF50',
  synced_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, google_course_id)
);

CREATE TABLE IF NOT EXISTS classroom_tasks (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  google_task_id   text NOT NULL,
  course_id        uuid REFERENCES classroom_courses(id) ON DELETE SET NULL,
  course_name      text NOT NULL DEFAULT '',
  course_color_hex text NOT NULL DEFAULT '#4CAF50',
  title            text NOT NULL,
  description      text,
  due_at           timestamptz,
  classroom_link   text,
  state            text NOT NULL DEFAULT 'assigned'
                   CHECK (state IN ('assigned', 'turnedIn', 'returned')),
  notified_60m     boolean NOT NULL DEFAULT false,
  notified_30m     boolean NOT NULL DEFAULT false,
  notified_10m     boolean NOT NULL DEFAULT false,
  synced_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, google_task_id)
);

CREATE TABLE IF NOT EXISTS classroom_announcements (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  google_announce_id  text NOT NULL,
  course_id           uuid REFERENCES classroom_courses(id) ON DELETE SET NULL,
  course_name         text NOT NULL DEFAULT '',
  text                text,
  posted_at           timestamptz,
  is_read             boolean NOT NULL DEFAULT false,
  synced_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, google_announce_id)
);

ALTER TABLE classroom_connections  ENABLE ROW LEVEL SECURITY;
ALTER TABLE classroom_courses      ENABLE ROW LEVEL SECURITY;
ALTER TABLE classroom_tasks        ENABLE ROW LEVEL SECURITY;
ALTER TABLE classroom_announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_only" ON classroom_connections
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "owner_only" ON classroom_courses
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "owner_only" ON classroom_tasks
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "owner_only" ON classroom_announcements
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
