# Business Tinder

Blind cross-campus coffee chats for 180DC ESCP. Members sign in with their @180dc.org email, swipe through anonymous profiles, get matched every round, and collect passport stamps. P&O runs the rounds from the P&O tab.

The site is plain HTML hosted on **Netlify** (from this GitHub repo). Logins and data live in **Supabase** (free plan).

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole app |
| `config.js` | Your Supabase address and public key (step 4) |
| `supabase-setup.sql` | Creates the database and its access rules (step 1) |
| `netlify.toml` | Tells Netlify there is nothing to build |

## Setup (about an hour, once)

### 1. Create the database
1. Sign up at [supabase.com](https://supabase.com) with a 180DC account and create a project (free plan, region: Europe).
2. Open **SQL Editor → New query** and paste in all of `supabase-setup.sql`.
3. At the bottom, replace the two example emails with the real P&O admins (yours and Gab's), in lowercase.
4. Click **Run**. It should say "Success". Running it again later is safe.

### 2. Set up sign-in emails
Supabase's built-in email only reaches people on your Supabase team, at 2 emails an hour, so sign-in links need to go out through a real mailbox. The simplest is a 180DC Gmail account (ideally a shared P&O one):

1. On that Google account: **Manage account → Security → 2-Step Verification** (turn it on), then search for **App passwords** and create one called "Coffee Chats". Copy the 16-character password.
2. In Supabase: **Authentication → Emails → SMTP Settings → Enable custom SMTP**:
   - Sender email: that Gmail address
   - Sender name: `180DC Coffee Chats`
   - Host: `smtp.gmail.com`
   - Port: `587`
   - Username: that Gmail address
   - Password: the app password
3. **Authentication → Rate Limits**: raise "emails sent per hour" to about 100 for launch day (the default is 30).
4. Optional: **Authentication → Emails → Templates → Magic Link**, set the subject to "Your Coffee Chats sign-in link".

If App passwords don't show up, your Google Workspace admin has turned them off. Ask them, or use a free SMTP service like Brevo instead (it gives you the same five fields).

### 3. Put the code on GitHub
1. Create a new **private** repository, for example `coffee-chats`.
2. **Add file → Upload files**, drag in all the files from this folder, and commit.

### 4. Connect your Supabase project
1. In Supabase: **Project Settings → API Keys**. Copy the **Project URL** and the **publishable key** (or the legacy **anon** key).
2. In GitHub, open `config.js`, click the pencil, paste both values in, and commit.

This key is meant to be public. The database rules decide what each person can see.

### 5. Publish on Netlify
1. At [netlify.com](https://netlify.com): **Add new site → Import an existing project → GitHub**, then pick the repo.
2. Leave the build command empty. The publish directory is `.` (it reads this from `netlify.toml`). Click **Deploy**.
3. **Site configuration → Change site name**, for example `180dc-coffee-chats`. Your link is then `https://180dc-coffee-chats.netlify.app`.
4. Back in Supabase: **Authentication → URL Configuration**:
   - Site URL: your Netlify link
   - Redirect URLs: add your Netlify link

From now on, every commit to GitHub updates the site automatically.

### 6. Test it
1. Open the link, enter your @180dc.org email, and click the link in the email.
2. Join the deck. You should see a **P&O** tab, because your email is in the admin list.
3. Ask Gab and one person from another campus to join, then run a test round from the P&O tab.
4. Try a non-180DC email: it should be refused.

Before launch, clear the test data: in **SQL Editor**, run
`delete from public.rounds; delete from public.inbox; delete from public.public_docs;`
This keeps everyone's profiles but resets the rounds, matches and stats.

## Who can do what

- **Only @180dc.org emails** can sign in. This is checked in three places: the login page, the database refuses to create accounts for any other address, and every table checks the domain again.
- **Members** see everyone's blind card (codename, campus, skills, fun fact). Team and role are kept off the card so nobody can be identified; members see a real name, email, team and role only for their own matches.
- **Who meets whom:** always someone new, from another campus first. When nobody new is left on other campuses, someone from the same campus on a different team. The deck follows the same order.
- **P&O admins** (the `admins` table) see real names, picks and feedback, and run the rounds.

To add an admin later, run this in the SQL Editor:
`insert into public.admins (email) values ('name@180dc.org');`

To remove one:
`delete from public.admins where email = 'name@180dc.org';`
