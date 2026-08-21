# aws-login-headless: logging in as the right account

`aws-login-headless` (defined in `zshrc`) runs `aws sso login` with the
device-code flow on a headless machine (mini1/mini2) and prints a link you
open in a browser on another machine.

**The browser that opens the link decides the account, not the machine that
ran the command.** If that browser already has an AWS session cookie, the
login silently completes as that user — this is why opening a mini1 link on
the MacBook used to log in as the MacBook's account.

Two ways to get the right account:

1. **Private window (quick):** open the link in an incognito/private window
   and sign in with the target machine's account.
2. **Dedicated browser profile (recommended if frequent):** create one
   Chrome profile per AWS account (e.g. "AWS-mini1", "AWS-mini2"), keep each
   signed in as its machine's account, and open device-code links in the
   matching profile. To open a link directly in a profile from the terminal:

   ```sh
   open -na "Google Chrome" --args --profile-directory="Profile 2" "<url>"
   ```

   (Find the profile directory name at `chrome://version` in that profile.)
