# Marketing Dashboard

The request, content-plan, approval and posting hub for the Eman brands.

- **Website:** the files in this folder, hosted free on GitHub Pages.
- **Logins, data and files:** a free Supabase project.

## One-time setup (about 15 minutes)

### 1. Create the Supabase project
1. Go to https://supabase.com and sign up (free).
2. Click **New project**. Name it `marketing-dashboard`, choose a strong database password, and pick the region closest to your team (for example London or Frankfurt).
3. Wait about a minute while it is created.

### 2. Run the setup script
1. In your project, open **SQL Editor** → **New query**.
2. Open `supabase/setup.sql` from this repository, copy all of it, paste it in, and click **Run**.
3. You should see "Success. No rows returned."

This creates the tables, the access rules (who can see and change what), the approval lock and file storage.
4. Then run the **private setup snippet** you were given separately, the same way. It creates your owner invite and brings across your current team list, content series and the Eman Channel brand kit. It is kept out of this public repository on purpose.

### 3. Switch off email confirmation
Logins use usernames, not real emails, so confirmation emails must be off.

1. Go to **Authentication** → **Sign In / Providers** → **Email**.
2. Turn **Confirm email** off and save.

### 4. Connect the website to Supabase
1. Go to **Project Settings** → **API** (sometimes shown as **Data API**).
2. Copy the **Project URL** and the **anon public** key (newer projects may call it the **publishable** key).
3. In this repository, open `config.js`, paste them between the quotes, and commit the change.

The anon key is designed to be public. Your data is protected by the access rules in the setup script, not by hiding this key.

### 5. Switch on GitHub Pages
1. In the repository on GitHub, go to **Settings** → **Pages**.
2. Under **Build and deployment**, set **Source** to **Deploy from a branch**, choose **main** and **/ (root)**, and save.
3. After a minute or two, the page shows your site's address, for example `https://yourname.github.io/marketing-dashboard/`.

### 6. Create your own login
1. Open the site and choose **First time here?**
2. Username: `fatimah`. Invite code: the one in your private setup snippet.
3. Choose your password. You're in as the owner.

## Adding people

On the **Team** page:

- **Add team member:** name, a username, what they can see. The dashboard shows login details (link, username, one-time invite code) to send them. They open the link, choose **First time here?**, and set their own password.
- **Add brand contact:** for people at each brand who send requests. They only see the request form and their own requests.
- For people already on the team list, click **Create login**.

## Who can do what

| | Owner (you) | Manager | Editor | Editor + Posting | Brand contact |
|---|---|---|---|---|---|
| See all work | ✓ | ✓ | Own only | Own + approved | Own requests only |
| Approve work | ✓ | | | | Their own requests |
| Assign, move dates, delete | ✓ | ✓ | | | |
| Upload finished files | ✓ | ✓ | ✓ | ✓ | |
| Mark as scheduled / posted | ✓ | ✓ | | ✓ | |

These rules are enforced by the database, not just hidden on the page.

## Good to know

- **Forgotten password:** in Supabase go to **Authentication** → **Users**, find the person (their login shows as `username@login.eman-marketing.app`), and delete them. Then create a new invite for them on the Team page using the same username.
- **File size:** up to 50 MB per file on the free plan. For bigger videos, paste a Drive or Dropbox link instead.
- **Free plan limits:** 500 MB of data and 1 GB of file storage. A project that has no activity for a week is paused; open the Supabase dashboard and click **Restore** if that happens.
- **Your own web address:** later you can point something like `dashboard.emanchannel.tv` at GitHub Pages under **Settings** → **Pages** → **Custom domain**.
