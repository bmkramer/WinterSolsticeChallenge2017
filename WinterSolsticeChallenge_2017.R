#This script is an answer to the Winter Solstice Challenge from Egon Willighagen
#It attempts to assess OA availability of research output in ORCID and the references therein (1 layer deep)
#http://chem-bla-ics.blogspot.nl/2017/11/winter-solstice-challenge-what-is-your.html

#install.packages("rorcid")
#install.packages("rjson")
#install.packages("httpcache")
#library(rorcid)
#require(rjson)
#require(httpcache)

#STEP 1: Get list of DOIs from ORCID

#Documentation rorcid package https://github.com/ropensci/rorcid
#Info on how to work with tibbles: http://uc-r.github.io/tibbles
#Info on how to coerce list into a dataframe: https://stackoverflow.com/questions/28526860/r-turn-list-into-dataframe

#declare variable for ORCID record
#example: ORCID Bianca Kramer 0000-0002-5965-6560
var <- c("0000-0002-5965-6560")

#get name from ORCID
out <- as.orcid(x = var)
name_given <- out[[1]]$`orcid-bio`$`personal-details`$`given-names`$value
name_family <- out[[1]]$`orcid-bio`$`personal-details`$`family-name`$value

#The works() function in rorcid gets works data from an orcid data object. 
out <- works(orcid_id(var))
#pull out the variable for external identifiers (DOI and EID), this is a list
mylist <- out$data$`work-external-identifiers.work-external-identifier`
#coerce list into a dataframe
df_step1 <- setNames(do.call(rbind.data.frame, mylist), c("ID", "DOI"))
#subset only DOIs (get rid of rows with EIDs)
df_step1 <- subset(df_step1, ID %in% 'DOI')
#keep only column with DOIs 
df_step1 <- df_step1['DOI']
#keep only values starting with 10. (to exclude invalid DOIs)
#df_step1 <- df_step1[grep("10.", df_step1$DOI), ]
#row count, declare to variable
count1 <- nrow(df_step1)

#STEP 2 Collect DOIs of cited references via CrossRef API, if provided

#Documentation CrossRef REST API: https://github.com/CrossRef/rest-api-doc
#FAQ on accessing I4OC/OCC via CrossRef REST API: https://i4oc.org/#headingThree

#define function to accommodate NULL results
naIfNull <- function(cell){
  if(is.null(cell)) {
    return(NA)
  } else {
    return(cell)
  }
}

#create new dataframe with only CrossRef DOIs

#create empty dataframe
df_step2a <- data.frame(matrix(nrow = 1, ncol = 2 ))
#set column names of dataframe
colnames(df_step2a) = c("DOI","agency")

#check agency for each DOI, fill dataframe
for (i in 1:count1){
  tryCatch({
  doi <- df_step1$DOI[i]
  doi_character <- as.character(doi)
  #enter your email address in the line below (replace your@email.com), this helps CrossRef contact you if something is wrong
  url <- paste("https://api.crossref.org/works/",doi,"/agency?mailto=your@email.com",sep="")
  raw_data <- GET(url)
  rd <- httr::content(raw_data)
  agency <- rd$message$agency$id
  result <- c(
    naIfNull(doi_character),
    naIfNull(agency)
  )
  df_step2a <- rbind(df_step2a,result)
  }, error=function(e){})
}  
#subset only CrossRef DOIs
df_step2a <- subset(df_step2a,agency=="crossref")
#count number of DOIs
count2 <- nrow(df_step2a)

#collect DOIs of cited references, if provided

#create empty dataframe
df_step2b <- data.frame(matrix(nrow = 1, ncol = 2 ))
#set column names of dataframe
colnames(df_step2b) = c("citing DOI","DOI")

#run double loop to look up references for each citing article (i), and to get DOI for each cited reference (j)
for (i in 1:count2){
  tryCatch({
  doi <- df_step2a$DOI[i]
  doi_character <- as.character(doi)
  #enter your email address in the line below (replace your@email.com), this helps CrossRef contact you if something is wrong
  url <- paste("https://api.crossref.org/works/",doi,"?mailto=your@email.com",sep="")
  raw_data <- GET(url)
  rd <- httr::content(raw_data)
  count_loop <- rd$message$`reference-count`
  references <- rd$message$reference
  for (j in 1:count_loop){
    result <- c(
      naIfNull(doi_character),
      naIfNull(references[[j]]$DOI)
    )
    df_step2b <- rbind(df_step2b,result)
  }
  }, error=function(e){})
}
#count number of references
count3 <- nrow(df_step2b)
#subset DOIs of cited references (excluding NA's)
df_step2 <- subset(df_step2b,!is.na(DOI))
#count number of DOIs
count4 <- nrow(df_step2)

#STEP 3 Check OA availability with OADOI

#OAIDOI documentation: https://oadoi.org/about
#OADOI API v2 information: https://oadoi.org/api and https://oadoi.org/api/v2
#script excerpted from full OADOI script here: https://github.com/bmkramer/OADOI_API_R

#define function to get data from OADOI API and construct vector with relevant variables;
getDataOADOI <- function(doi){
  doi_character <- as.character(doi)
  #enter your email address in the line below (replace your@email.com), this helps OADOI contact you if something is wrong
  url <- paste("https://api.oadoi.org/v2/",doi,"?email=your@email.com",sep="")
  raw_data <- GET(url)
  rd <- httr::content(raw_data)
  first_result <- rd
  best_location <- rd$best_oa_location
  result <- c(
    doi_character,
    naIfNull(first_result$is_oa),
    naIfNull(best_location$host_type),
    naIfNull(best_location$license),
    naIfNull(best_location$version),
    naIfNull(best_location$url),
    naIfNull(first_result$journal_is_oa)
  )
  return(result)
}

#check OA availability of each ORCID DOI (level_0)

#create empty dataframe with 7 columns
df <- data.frame(matrix(nrow = 1, ncol =7))
colnames(df) = c("DOI", "is_oa", "host_type", "license", "version", "URL", "journal_is_oa")
#fill dataframe
for (i in 1:count1){
  tryCatch({
  df <- rbind(df,getDataOADOI(df_step1$DOI[i]))
  }, error=function(e){})
}
df_level_0 <- df
#subset is_oa = TRUE
df_level_0  <-subset(df_level_0 , is_oa == TRUE)
count5 <- nrow(df_level_0)

#check OA availability of each referenced DOI (level_1)

#create empty dataframe with 7 columns
df <- data.frame(matrix(nrow = 1, ncol =7))
colnames(df) = c("DOI", "is_oa", "host_type", "license", "version", "URL", "journal_is_oa")
#fill dataframe
for (i in 1:count4){
  tryCatch({
  df <- rbind(df,getDataOADOI(df_step2$DOI[i]))
  }, error=function(e){})
}
df_level_1 <- df
#subset is_oa = TRUE
df_level_1  <-subset(df_level_1 , is_oa == TRUE)
count6 <- nrow(df_level_1)

#STEP 4: calculate %OA for level_0 / level_1 / final

# %OA for level_0 
OA_level_0 <- round(count5/count1,digits=2)
# %OA for level_1
OA_level_1 <- round(count6/count4,digits=2)
# %OA level final (counting level_0 as 1, level_1 as 0.5)
OA_level <- round(((OA_level_0 + 0.5*(OA_level_1))/1.5),digits=2)

#print summary
cat(name_given, name_family,
    "\n",count1,"DOIs in ORCID, of which",count2,"in CrossRef",  
    "\n",count3,"references in CrossRef, of which",count4,"with DOI",
    "\n","level 0:",OA_level_0*100,"% OA",
    "\n","level 1:",OA_level_1*100,"% OA",
    "\n","final score:",OA_level*100,"% OA")