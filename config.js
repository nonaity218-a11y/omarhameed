// استدعاء مكتبة Supabase
import { createClient } from '@supabase/supabase-js';

// رابط مشروعك ومفتاح الـ Anon
const SB_URL = 'https://giaccacvjyjwdzqlridc.supabase.co';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpYWNjYWN2anlqd2R6cWxyaWRjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODM2MDMsImV4cCI6MjEwNjM1OTYwM30.NPPWlur2HOMIpdoPaZUDT1Sbur8hW9OLqfWIZpkN5aM';

// إنشاء الاتصال بقاعدة البيانات
export const sb = createClient(SB_URL, SB_KEY);
