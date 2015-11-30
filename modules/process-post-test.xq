xquery version "3.1";

(: import tweets stored as .json files in import collection :)

import module namespace ju = "http://joewiz.org/ns/xquery/json-util" at "json-util.xqm";

let $json := json-doc('/db/apps/tumblr/import/54512480673.json')
let $posts := $json?response?posts
for $post in $posts?*
return
    (
        ju:advise($post)
    )