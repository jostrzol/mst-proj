DECLARE @Tag NVARCHAR(35) = 'rust';

DECLARE @TagId INT;
SELECT @TagId = Id FROM Tags
WHERE TagName = @Tag;

SELECT DISTINCT PostId
INTO #SelectedPostIds
FROM PostTags
WHERE TagId = @TagId;

SELECT TOP 30
    T.TagName,
    COUNT(*) AS Count
FROM PostTags AS Pt
INNER JOIN Tags AS T ON (Pt.TagId = T.Id)
WHERE Pt.PostId IN (SELECT Pt.PostId FROM #SelectedPostIds)
GROUP BY Pt.TagId, T.TagName
HAVING Pt.TagId <> @TagId
ORDER BY COUNT(*) DESC;
