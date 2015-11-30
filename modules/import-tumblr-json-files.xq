xquery version "3.1";

(: import tweets stored as .json files in import collection :)

import module namespace ptp="http://history.state.gov/ns/xquery/tumblr/process-tumblr-posts" at "process-tumblr-posts.xqm";

let $import-col := '/db/apps/tumblr/import'
let $files := xmldb:get-child-resources($import-col)
let $paths := $files ! concat($import-col, '/', .)
for $path in $paths
let $json := json-doc($path)
for $post in $json?response?posts?*
let $post-xml := ptp:post-json-to-xml($post, 'HistoryAtState')
return
    ptp:store-post-xml($post-xml)