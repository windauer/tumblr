xquery version "3.1";

module namespace ptp="http://history.state.gov/ns/xquery/tumblr/process-tumblr-posts";

import module namespace ju = "http://joewiz.org/ns/xquery/json-util" at "json-util.xqm";
import module namespace functx="http://www.functx.com";

declare function ptp:trim-phrase-to-length($phrase, $length) {
    let $words := tokenize(normalize-space($phrase), '\s+')
    let $do-not-end-with-these-words := ('a', 'of', 'this', 'for', 'the', 'as', 'with', 'in', 'to')
    return
        if (string-length(string-join($words, ' ')) le $length) then string-join($words, $length)
        else 
            let $best-fit := 
                max(
                    for $n in (1 to count($words))
                    let $subset := subsequence($words, 1, $n)
                    let $subset-length := string-length(string-join($subset, ' '))
                    return if ($subset-length le $length and not(lower-case($words[$n]) = $do-not-end-with-these-words)) then $n else ()
                )
            let $snipped-phrase := string-join(subsequence($words, 1, $best-fit), ' ')
            return 
                if (matches($snipped-phrase, '\.$')) then 
                    $snipped-phrase
                else if (matches($snipped-phrase, '[,:;]$')) then 
                    concat(substring($snipped-phrase, 1, string-length($snipped-phrase) - 1), '...')
                else 
                    concat($snipped-phrase, '...')
};

declare function ptp:post-json-to-xml($post as map(*), $default-blog-name as xs:string?) {
    let $id := $post?id cast as xs:decimal
    let $created-datetime := 
        let $date := $post?date
        let $date-tokens := tokenize($date, '\s')
        let $datetime := concat($date-tokens[1], 'T', $date-tokens[2], 'Z')
        return
            adjust-dateTime-to-timezone(xs:dateTime($datetime))
    let $url := $post?post_url
    let $short-title := 
        if ($post?title) then 
            $post?title
        else if ($post?type = 'photo') then 
            let $parsed-caption := util:parse(concat('<div>', $post?caption, '</div>'))/node()
            let $paras := 
                for $para in $parsed-caption//*:p[not(.//*:p)]
                return if (not(matches($para, '[.,:?]$'))) then concat($para, ': ') else $para/string()
            let $candidate-title := string-join($paras, ' ')
            return
                ptp:trim-phrase-to-length($candidate-title, 140)
        else 
            <span>unknown Tumblr content type {$post?type}</span>
    return 
        <post>
            <id>{$id}</id>
            <date>{$created-datetime}</date>
            <blog-name>{$default-blog-name}</blog-name>
            <url>{$url}</url>
            <short-title>{$short-title}</short-title>
        </post>
};

(: Helper functions to recursively create a collection hierarchy. :)

declare function ptp:mkcol($collection, $path) {
    ptp:mkcol-recursive($collection, tokenize($path, "/"))
};

declare function ptp:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            xmldb:create-collection($collection, $components[1]),
            ptp:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        ()
};

(: Store the transformed tweet into the database :)
declare function ptp:store-post-xml($post-xml) {
    let $blog-name := $post-xml/blog-name
    let $created-datetime := xs:dateTime($post-xml/date)
    let $year := year-from-date($created-datetime)
    let $month := functx:pad-integer-to-length(month-from-date($created-datetime), 2)
    let $day := functx:pad-integer-to-length(day-from-date($created-datetime), 2)
    let $destination-col := string-join(('/db/apps/tumblr/data', $blog-name, $year, $month, $day), '/')
    let $id := $post-xml/id
    let $filename := concat($id, '.xml')
    let $prepare-collection := 
        if (xmldb:collection-available($destination-col)) then 
            () 
        else 
            ptp:mkcol('/db/apps/tumblr/data', string-join(($blog-name, $year, $month, $day), '/'))
    return
        xmldb:store($destination-col, $filename, $post-xml)
};