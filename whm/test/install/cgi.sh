# Sourced by run.sh. Runs the installed CGI the way cpsrvd would:
#   cgi METHOD QUERY [BODY]   -> /tmp/cgi.out (headers and body), /tmp/cgi.err
D=/usr/local/cpanel/whostmgr/docroot
cgi() {
    body=${3:-}
    printf '%s' "$body" | env -i PATH=/usr/bin:/bin REQUEST_METHOD="$1" QUERY_STRING="$2" \
        CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=${#body} \
        cp_security_token=/cpsess7777777777 REMOTE_USER=root HTTP_HOST=host.example:2087 \
        FAKE_ACL="${FAKE_ACL:-all}" FAKE_LOCALE="${FAKE_LOCALE:-en}" \
        $D/cgi/infrafence/index.cgi > /tmp/cgi.out 2>/tmp/cgi.err
}
