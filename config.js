// ضع بيانات مشروعك من Supabase > Project Settings > API
const SB_URL = 'https://sb_publishable_wtMAZ4Ar1hKayq3Hbr72uw_Khjb9Ofz';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpYWNjYWN2anlqd2R6cWxyaWRjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODM2MDMsImV4cCI6MjEwNjM1OTYwM30.NPPWlur2HOMIpdoPaZUDT1Sbur8hW9OLqfWIZpkN5aM';
const sb = supabase.createClient(SB_URL, SB_KEY);
