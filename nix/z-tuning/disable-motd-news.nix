# motd-news — Ubuntu's "Message of the Day" news fetcher.
#
# WHY DISABLE: Runs wget in the background to fetch marketing/news from
# Canonical's servers every login. On a build server this is unnecessary
# network traffic and a wasted process. Also runs on a timer, waking up
# periodically even when nobody is logging in.
{
  name = "disable-motd-news";
  description = "motd-news — fetches Canonical news via wget on every login";
  script = ''
    disable_service motd-news.service
    disable_service motd-news.timer
    # Also disable the script itself so it doesn't run via pam
    if [ -x /etc/update-motd.d/50-motd-news ]; then
      chmod -x /etc/update-motd.d/50-motd-news
      echo "  disabled /etc/update-motd.d/50-motd-news"
    fi
  '';
}
