xquery version "3.0";

module namespace tumblr-client = "http://history.state.gov/ns/xquery/tumblr-client";

import module namespace tumblr = "http://history.state.gov/ns/xquery/tumblr" at "tumblr.xq";
import module namespace dates = "http://xqdev.com/dateparser" at "../../../modules/date-parser.xqm";
import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";
import module namespace web-apis = "http://history.state.gov/ns/xquery/web-api-utils" at "web-api-utils.xq";

declare variable $tumblr-client:consumer-key := 'LC0zps2AU68aScWwq2wzW4xEFbYzIvfFcNTofxyJkRsyE8vWr9';
declare variable $tumblr-client:consumer-secret := 'dKcghSh9NIiCw0NdpSZwO4y08SwEFrXjE38UDPNf1yG6jl8VuP';
declare variable $tumblr-client:base-hostname := 'HistoryAtState.tumblr.com';

declare variable $tumblr-client:data-collection := '/db/cms/apps/social-media/data/tumblr';
declare variable $tumblr-client:import-collection := '/db/cms/apps/social-media/import/tumblr';
declare variable $tumblr-client:logs-collection := '/db/cms/apps/social-media/import-logs/tumblr';

(: clean up HTML from tumblr :)

declare function tumblr-client:render($node) {
    typeswitch($node)
        case text() return $node
        case element(p) return tumblr-client:p($node)
        case element(a) return tumblr-client:a($node)
        case element(span) return tumblr-client:span($node)
        case element() return element {node-name($node)} {$node/@*, tumblr-client:recurse($node)}
        default return tumblr-client:recurse($node)
};

declare function tumblr-client:recurse($node) {
    for $child in $node/node()
    return
        tumblr-client:render($child)
};

declare function tumblr-client:p($node) {
    if (normalize-space($node) = ('', '&#160;') and not($node/*)) then
        () 
    else 
        element {node-name($node)} {tumblr-client:recurse($node)}
};

declare function tumblr-client:a($node) {
    if ($node/parent::a) then
        tumblr-client:recurse($node)
    else 
        element {node-name($node)} {$node/@*[not(name(.) = 'target')], tumblr-client:recurse($node)}
};

declare function tumblr-client:span($node) {
    if ($node/@*) then
        element {node-name($node)} {$node/@*, tumblr-client:recurse($node)}
    else 
        tumblr-client:recurse($node)
};

declare function tumblr-client:trim-phrase-to-length($phrase, $length) {
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
                else concat($snipped-phrase, '...')
};

declare function tumblr-client:process-response($request-response as item()+) {
    let $start-time := util:system-dateTime()
    let $request := $request-response[1]
    let $response-head := $request-response[2]
    let $response-body := $request-response[3]
    let $json := util:binary-to-string($response-body)
    let $raw-xml := xqjson:parse-json($json)
    let $posts := $raw-xml/pair[@name='response']/pair[@name='posts']/item
    return 
        if (empty($posts)) then 
            <result>
                <records-stored>{count($posts)}</records-stored>
                <summary>no posts!</summary>
                {$request, $response-head, $raw-xml}
            </result>
        else
        
    let $ids := $posts/pair[@name = 'id']/string()
    let $ordered-ids := for $id in $ids order by $id ascending return $id
    let $id-span := 
        if (count($ids) gt 1) then 
            concat($ordered-ids[1], '-', $ordered-ids[last()])
        else 
            $ids
    let $store-json := xmldb:store($tumblr-client:import-collection, concat($id-span, '.json'), $json)
    let $request-log := 
        <request-log>
            <request-dateTime>{util:system-dateTime()}</request-dateTime>
            {$request, $response-head}    
        </request-log>
    let $store-log := xmldb:store($tumblr-client:logs-collection, concat($id-span, '-request-log.xml'), $request-log)
    let $store-entry := 
        for $post in $posts 
        let $source := web-apis:unjsonify($post)
        let $id := $source/id/string()
        let $created-datetime := 
            let $date := $source/date
            let $date-tokens := tokenize($date, '\s')
            let $datetime := concat($date-tokens[1], 'T', $date-tokens[2], 'Z')
            return
                adjust-dateTime-to-timezone(xs:dateTime($datetime))
        let $url := $source/post_url/string()
        let $content := 
            if ($source/title) then 
                $source/title/string()
            else if ($source/type='photo') then 
                let $parsed-caption := util:parse(concat('<div xmlns="http://www.w3.org/1999/xhtml">', $source/caption/node(), '</div>'))/node()
                let $paras := 
                    for $para in $parsed-caption//*:p[not(.//*:p)]
                    return if (not(matches($para, '[.,:?]$'))) then concat($para, ': ') else $para/string()
                let $candidate-title := string-join($paras, ' ')
                return
                    tumblr-client:trim-phrase-to-length($candidate-title, 140)
            else 
                <span>unknown Tumblr content type {$source/type/string()}</span>
        let $entry :=  
            <entry>
                <id>{$id}</id>
                <service-name>tumblr</service-name>
                <retrieved-datetime>{util:system-dateTime()}</retrieved-datetime>
                <extract>
                    <generated-datetime>{util:system-dateTime()}</generated-datetime>
                    <created-datetime>{$created-datetime}</created-datetime>
                    <content><div xmlns="http://www.w3.org/1999/xhtml" class="tumblr-post">{$content}</div></content>
                    <public-url>{$url}</public-url>
                </extract>
                <source>{$source}</source>
            </entry>
        return
            xmldb:store($tumblr-client:data-collection, concat($id, '.xml'), $entry)
    let $completed-time := util:system-dateTime()
    return
        <result>
            <records-stored>{count($posts)}</records-stored>
            <duration>{$completed-time - $start-time}</duration>
            <request-log>{$store-log}</request-log>
            <json-archive>{$store-json}</json-archive>
            <entries>{for $entry in $store-entry order by $entry return <entry>{$entry}</entry>}</entries>
        </result>
};

declare function tumblr-client:crawl-blog-posts($limit as xs:integer, $offset as xs:integer) {
    let $response := tumblr:blog-posts($tumblr-client:consumer-key, $tumblr-client:base-hostname, (), (), (), $limit, $offset, (), (), ())
    let $result := tumblr-client:process-response($response)
    return 
        (
        $result
        ,
        if (xs:integer($result/records-stored) = 0) then 
            (
            <result>done - no more posts to crawl</result>
            ,
            if (doc-available(concat($tumblr-client:logs-collection, '/crawl-blog-posts-state.xml'))) then xmldb:remove($tumblr-client:logs-collection, 'crawl-blog-posts-state.xml') else ()
            ,
            xmldb:store($tumblr-client:logs-collection, 'last-crawl.xml', <last-crawl><datetime>{util:system-dateTime()}</datetime></last-crawl>)
            )
        else
            (
            xmldb:store($tumblr-client:logs-collection, 'crawl-blog-posts-state.xml', $result)
            ,
            let $new-offset := $offset + $limit
            return
                tumblr-client:crawl-blog-posts($limit, $new-offset)
            )
        )
};


declare function tumblr-client:initiate-blog-posts-crawl() {
    let $update-in-progress := doc-available(concat($tumblr-client:logs-collection, '/update-blog-posts-state.xml'))
    return
        if ($update-in-progress) then
            <result>user-timeline is being updated, come back later to crawl</result>
        else
            
    let $store-lock := xmldb:store($tumblr-client:logs-collection, 'crawl-blog-posts-state.xml', <started/>)
    let $limit := 10
    let $offset := 0 (: first post :)
    return 
        tumblr-client:crawl-blog-posts($limit, $offset)
};

declare function tumblr-client:update-blog-posts($limit as xs:integer, $offset as xs:integer) {
    let $response := tumblr:blog-posts($tumblr-client:consumer-key, $tumblr-client:base-hostname, (), (), (), $limit, $offset, (), (), ())
    let $result := tumblr-client:process-response($response)
    return 
        (
        $result
        ,
        <result>done - no more posts to update</result>
        ,
        if (doc-available(concat($tumblr-client:logs-collection, '/update-blog-posts-state.xml'))) then xmldb:remove($tumblr-client:logs-collection, 'update-blog-posts-state.xml') else ()
        ,
        xmldb:store($tumblr-client:logs-collection, 'last-update.xml', <last-update><datetime>{util:system-dateTime()}</datetime></last-update>)
        )
};

declare function tumblr-client:initiate-blog-posts-update() {
    let $posts-in-archive := count(collection($tumblr-client:data-collection)/entry)
    let $posts-available := xs:integer(xqjson:parse-json(util:binary-to-string(tumblr:blog-info($tumblr-client:consumer-key, $tumblr-client:base-hostname)[3]))//pair[@name = 'posts']/string())

    let $how-many-to-fetch := $posts-available - $posts-in-archive
    return
        if ($how-many-to-fetch eq 0) then 
            (
                <result>no new posts</result>,
                xmldb:store($tumblr-client:logs-collection, 'last-update.xml', <last-update><datetime>{util:system-dateTime()}</datetime></last-update>)
            )
        else
            let $update-in-progress := 
                (
                   doc-available(concat($tumblr-client:logs-collection, '/update-blog-posts-state.xml'))
                   and
                   current-dateTime() - xmldb:last-modified($tumblr-client:logs-collection, 'update-blog-posts-state.xml') lt xs:dayTimeDuration('PT2M')
                )
            return
                if ($update-in-progress) then
                    <result>blog posts are being crawled (since {xmldb:last-modified($tumblr-client:logs-collection, 'update-blog-posts-state.xml')}). come back in ~2 min to update</result>
                else
                    let $store-lock := xmldb:store($tumblr-client:logs-collection, 'update-blog-posts-state.xml', <started/>)
                    let $offset := 0
                    let $limit := $how-many-to-fetch
                    return
                        tumblr-client:update-blog-posts($limit, $offset)
};

declare function tumblr-client:echo-response($request-response as item()+) {
    let $request := $request-response[1]
    let $response-head := $request-response[2]
    let $response-body := $request-response[3]
    let $json := util:binary-to-string($response-body)
    let $raw-xml := xqjson:parse-json($json)
    return 
        (
        $request, 
        $response-head,
        $raw-xml,
        web-apis:unjsonify($raw-xml)
        )
};

declare function tumblr-client:populate() {
    xmldb:create-collection('/db/cms/apps/social-media', 'data'),
    xmldb:create-collection('/db/cms/apps/social-media/data', 'tumblr'),
    xmldb:create-collection('/db/cms/apps/social-media/', 'import'),
    xmldb:create-collection('/db/cms/apps/social-media/import', 'tumblr'),
    xmldb:create-collection('/db/cms/apps/social-media/', 'import-logs'),
    xmldb:create-collection('/db/cms/apps/social-media/import-logs', 'tumblr'),

    tumblr-client:initiate-blog-posts-crawl(),
    tumblr-client:initiate-blog-posts-update()
};

declare function tumblr-client:repopulate() {
    (:tumblr-client:clean(),:)
    tumblr-client:populate()
};
