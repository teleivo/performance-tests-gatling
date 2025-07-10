-- this is one of the queries executed by ./src/test/java/org/hisp/dhis/test/TrackerExporterTests.java
-- the test executes another variant which is the count
\set param1 '890614'
\set param2 'xE7jOejl9FI'
\set param3 '2024-01-01 00:00:00'
\set param4 '2024-12-31 23:59:59.999'
\set param5 'q04UBOqq3rp'
\set param6 'eBAyeGv0exc'
\set param7 'MoUd5BTQ3lY'
\set param8 'lxAQ7Zs9VYR'
\set param9 'M3xtLkYBlKI'
\set param10 'qDkgAbB5Jlk'
\set param11 'VBqh0ynB2wv'
\set param12 'uy2gU8kT1jF'
\set param13 'bMcwwoVnbSR'
\set param14 'fDd25txQckK'
\set param15 'IpHINAT79UW'
\set param16 'kla3mAPgvCH'
\set param17 'ur1Edk5Oe2n'
\set param18 'WSGAb5XwJ3Y'

explain (analyze, costs, verbose, buffers, format json)
select *
from
    (
        select
            ev.uid as ev_uid,
            ou.uid as orgunit_uid,
            ou.code as orgunit_code,
            ou.name as orgunit_name,
            ou.attributevalues as orgunit_attributevalues,
            p.uid as p_uid,
            p.code as p_code,
            p.name as p_name,
            p.attributevalues as p_attributevalues,
            ps.uid as ps_uid,
            ps.code as ps_code,
            ps.name as ps_name,
            ps.attributevalues as ps_attributevalues,
            ev.eventid as ev_id,
            ev.status as ev_status,
            ev.occurreddate as ev_occurreddate,
            ev.eventdatavalues as ev_eventdatavalues,
            ev.completedby as ev_completedby,
            ev.storedby as ev_storedby,
            ev.created as ev_created,
            ev.createdatclient as ev_createdatclient,
            ev.createdbyuserinfo as ev_createdbyuserinfo,
            ev.lastupdated as ev_lastupdated,
            ev.lastupdatedatclient as ev_lastupdatedatclient,
            ev.lastupdatedbyuserinfo as ev_lastupdatedbyuserinfo,
            ev.completeddate as ev_completeddate,
            ev.deleted as ev_deleted,
            st_astext(ev.geometry) as ev_geometry,
            au.uid as user_assigned,
            (au.firstname || ' ' || au.surname) as user_assigned_name,
            au.firstname as user_assigned_first_name,
            au.surname as user_assigned_surname,
            au.username as user_assigned_username,
            coc_agg.uid as coc_uid,
            coc_agg.code as coc_code,
            coc_agg.name as coc_name,
            coc_agg.attributevalues as coc_attributevalues,
            coc_agg.co_values as co_values,
            coc_agg.co_count as option_size,
            en.uid as en_uid,
            p.type as p_type
        from event ev
        inner join enrollment en on en.enrollmentid = ev.enrollmentid
        inner join program p on p.programid = en.programid
        inner join programstage ps on ps.programstageid = ev.programstageid
        left join
            trackedentityprogramowner po
            on (en.trackedentityid = po.trackedentityid and en.programid = po.programid)
        inner join
            organisationunit evou
            on (coalesce(po.organisationunitid, ev.organisationunitid) = evou.organisationunitid)
        inner join organisationunit ou on (ev.organisationunitid = ou.organisationunitid)
        left join trackedentity te on te.trackedentityid = en.trackedentityid
        left join userinfo au on (ev.assigneduserid = au.userinfoid)
        inner join
            (
                select
                    coc.uid,
                    coc.code,
                    coc.name,
                    coc.attributevalues,
                    coc.categoryoptioncomboid as id,
                    jsonb_object_agg(
                        co.uid,
                        jsonb_build_object(
                            'name', co.name, 'code', co.code, 'attributeValues', co.attributevalues
                        )
                    ) as co_values,
                    count(co.categoryoptionid) as co_count
                from categoryoptioncombo coc
                inner join
                    categoryoptioncombos_categoryoptions cocco
                    on coc.categoryoptioncomboid = cocco.categoryoptioncomboid
                inner join categoryoption co on cocco.categoryoptionid = co.categoryoptionid
                group by coc.categoryoptioncomboid
                having
                    bool_and(
                        case
                            when
                                (
                                    co.sharing ->> 'owner' is null
                                    or co.sharing ->> 'owner' = 'xE7jOejl9FI'
                                )
                                or co.sharing ->> 'public' like '__r_____'
                                or co.sharing ->> 'public' is null
                                or (
                                    jsonb_has_user_id(co.sharing, 'xE7jOejl9FI') = true
                                    and jsonb_check_user_access(
                                        co.sharing, 'xE7jOejl9FI', '__r_____'
                                    )
                                    = true
                                )
                                or (
                                    jsonb_has_user_group_ids(
                                        co.sharing,
                                        '{B6JNeAQ6akX,GogLpGmkL0g,H9XnHoWRKCg,Kk12LkEWtXp,M1Qre0247G3,NTC8GjJ7p8P,QYrzIjSfI8z,gXpmQO6eEOo,jvrEwEJ2yZn,lFHP5lLkzVr,tH0GcNZZ1vW,vAvEltyXGbD,vRoAruMnNpB,w900PX10L7O,wl5cDMuUhmF,z1gNAf2zUxZ}'
                                    )
                                    = true
                                    and jsonb_check_user_groups_access(
                                        co.sharing,
                                        '__r_____',
                                        '{B6JNeAQ6akX,GogLpGmkL0g,H9XnHoWRKCg,Kk12LkEWtXp,M1Qre0247G3,NTC8GjJ7p8P,QYrzIjSfI8z,gXpmQO6eEOo,jvrEwEJ2yZn,lFHP5lLkzVr,tH0GcNZZ1vW,vAvEltyXGbD,vRoAruMnNpB,w900PX10L7O,wl5cDMuUhmF,z1gNAf2zUxZ}'
                                    )
                                    = true
                                )
                            then true
                            else false
                        end
                    )
                    = true
            ) as coc_agg
            on coc_agg.id = ev.attributeoptioncomboid
        where
            p.programid = :'param1'
            and exists (
                select cs.organisationunitid
                from usermembership cs
                join organisationunit orgunit on orgunit.organisationunitid = cs.organisationunitid
                join userinfo u on u.userinfoid = cs.userinfoid
                where u.uid = :'param2' and ou.path like concat(orgunit.path, '%')
            )
            and ev.occurreddate >= :'param3'
            and ev.occurreddate <= :'param4'
            and p.type = 'WITHOUT_REGISTRATION'
            and ev.deleted is false
            and (p.uid in (:'param5', :'param6', :'param7', :'param8', :'param9', :'param10', :'param11', :'param12', :'param13', :'param14', :'param15', :'param16', :'param17', :'param18'))
        order by ev_id desc
        limit 101
        offset 0
    ) as event
left join
    (
        select
            evn.eventid as evn_id,
            n.noteid as note_id,
            n.notetext as note_text,
            n.created as note_created,
            n.creator as note_creator,
            n.uid as note_uid,
            userinfo.userinfoid as note_user_id,
            userinfo.code as note_user_code,
            userinfo.uid as note_user_uid,
            userinfo.username as note_user_username,
            userinfo.firstname as note_user_firstname,
            userinfo.surname as note_user_surname
        from event_notes evn
        inner join note n on evn.noteid = n.noteid
        left join userinfo on n.lastupdatedby = userinfo.userinfoid
    ) as cm
    on event.ev_id = cm.evn_id
order by ev_id desc
;

