# Holistic Academy School Management: Setup Guide

You have two files:

- **holistic_academy_sms.html** is the whole app. Open it in any browser on a computer or phone.
- **supabase_setup.sql** creates the shared online database. You run it once.

## Try it straight away (demo mode)

Open the HTML file and click one of the demo roles on the sign-in screen (Proprietor, Administrator, Headmistress, Treasurer, Teacher). In demo mode, records are saved only in that browser on that device, so use it for trying the app and training staff.

## Connect the online database (one time, about 15 minutes)

This is what lets many staff work at the same time and lets the Proprietor see everything from anywhere.

1. Create a free account at **supabase.com**, then click **New project**. Choose a strong database password and the region closest to Ghana (for example *West EU*).
2. Open **SQL Editor → New query**, paste everything from `supabase_setup.sql`, and click **Run**. It should say *Success*.
3. Go to **Authentication → Sign In / Providers → Email** and switch **Confirm email** off. If you leave it on, every new staff member must click a link in their email before they can sign in.
4. Click **Connect** at the top of your project (or go to **Project Settings → API**) and copy the **Project URL** and the **anon public** key.
5. Put them in the app. You can do this in either of two ways:
   - **Recommended:** open the HTML file in a text editor (Notepad is fine). Near the top of the script, fill in the two lines `const SUPABASE_URL = '';` and `const SUPABASE_ANON_KEY = '';`, then save. Every copy of this file then connects automatically.
   - Or, on each device, open the app and go to **⚙ Database connection** on the sign-in screen, paste both values, and click **Save & Connect**.
6. **The Proprietor creates the first account** with *New staff? Create account*. The first account ever created automatically becomes the Proprietor.
7. Add staff in either of two ways. The Proprietor (or Admin) can go to **Admin → Staff Accounts → Add Staff Account**, then give each person their email and password. Or staff can create their own accounts on the sign-in screen, and the Proprietor approves each one in **Admin → Staff Accounts** by choosing a role (and a class for teachers) and clicking **Save**.

The anon key is safe to put in the file. Supabase designed it to be public. What protects the data is the set of database rules that `supabase_setup.sql` installs.

## Putting the app online so the Proprietor can open it anywhere

The records live in the online database, so any copy of the HTML file shows the same, current information. Pick any of these:

- **Netlify Drop** (easiest): go to app.netlify.com/drop and drag the HTML file onto the page. You get a web link you can bookmark on every phone and computer.
- **GitHub Pages**: upload the file to a repository and turn on Pages.
- **Send the file** to staff on WhatsApp or by email and open it on the phone. This works too. Re-send it whenever you get an updated version.

## Who can do what

| | Proprietor | Admin | Headmistress | Treasurer | Teacher |
|---|:-:|:-:|:-:|:-:|:-:|
| Dashboard & printable reports | ✅ | ✅ | ✅ | ✅ | ✅ (no money) |
| Enrol / edit students | ✅ | ✅ | ✅ | — | — |
| Attendance, grades, incidents | ✅ | ✅ | ✅ | — | ✅ own class |
| School fees, feeding fees, expenses | ✅ | ✅ | ✅ | ✅ | — |
| Payroll | ✅ | ✅ | — | — | — |
| Admin page (staff, classes, fees, activity log, import, backup) | ✅ | ✅ | — | — | — |

The database itself enforces these rules, not only the screen. A teacher's login cannot read fees, expenses or payroll, even if someone edits the web page.

## First things to set in Admin

- **School Setup:** school name, academic year, current term, fee per class, whether fees are charged per month or per term, and the feeding fee per child.
- **Classes & Subjects:** Nursery 1 to Primary 2 are switched on. When the school opens Primary 3 (and later JHS 1–3), tick it and click Save.
- **Data & Backup → Import old data:** this brings in records from the old Google Sheet system. Click **1. Check old data** first to see what will come in, then **2. Import old data**. Duplicate records from the old system are removed, and running the import twice never copies anything.
- **Data & Backup → Download backup:** do this once a month and keep the file somewhere safe.

## End of the school year

Go to **Students → Promote Classes** and promote the highest class first (for example Primary 2 → Primary 3, then Primary 1 → Primary 2, and so on). Then update the academic year in **Admin → School Setup**.

## If something goes wrong

- *"Your account is waiting for approval"*: the Proprietor or Admin must give that person a role in Admin → Staff Accounts.
- *"Could not reach the database"*: check the internet connection, then click Save again. Each form keeps the same record ID until it saves, so retrying never creates a copy.
- If the Proprietor ever gets locked out, run this in the Supabase SQL Editor (put in the real email): `update profiles set role = 'proprietor', active = true where email = 'name@example.com';`
