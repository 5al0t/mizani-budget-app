"""Generate signing export options without interpolating user input into shell/XML."""
import os
import plistlib
import sys

options = {
    "method": os.environ["APP_EXPORT_METHOD"],
    "teamID": os.environ["APP_TEAM_ID"],
    "signingStyle": "manual",
    "signingCertificate": "Apple Distribution",
    "provisioningProfiles": {os.environ["APP_BUNDLE_ID"]: os.environ["APP_PROFILE_NAME"]},
    "uploadSymbols": True,
}
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(options, stream)
