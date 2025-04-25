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
FROM PostTags AS PT
INNER JOIN Tags AS T ON (PT.TagId = T.Id)
WHERE PT.PostId IN (SELECT SPI.PostId FROM #SelectedPostIds AS SPI)
GROUP BY PT.TagId, T.TagName
HAVING PT.TagId <> @TagId
ORDER BY COUNT(*) DESC;
