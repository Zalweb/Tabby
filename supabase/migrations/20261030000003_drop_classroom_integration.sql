-- Google Classroom is retired: the app never shipped a working sync path, the
-- feature is being removed from the client, and the tables held two connection
-- rows with no courses, tasks or announcements behind them.

DROP TABLE IF EXISTS public.classroom_announcements;
DROP TABLE IF EXISTS public.classroom_tasks;
DROP TABLE IF EXISTS public.classroom_courses;
DROP TABLE IF EXISTS public.classroom_connections;
