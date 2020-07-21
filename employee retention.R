setwd('/Users/zhanghanduo/Desktop/data/employee\ retention')
rm(list = ls())
library(dplyr)
library(ggplot2)
library(pROC)
library("readxl")
library("tidyverse")
library(randomForest)
library(gbm)
library(caret)

############################################################################################################
### import data

df = read.csv('employee_retention_data.csv')
attach(df)
#############################exploratory data analysis

mode(df$join_date)
mode(df$quit_date)
df$join_date = as.Date(df$join_date)
df$quit_date = as.Date(df$quit_date)
df$company_id = as.factor(df$company_id)
df$employee_id = as.factor(df$employee_id)
summary(df) # not quit :11192, 45.3%
cor(seniority,salary) #0.5594652

plot(df$seniority,main = 'seniority',xlab = 'index',ylab = 'seniority')#2 outliers 
sort(unique(df$seniority),decreasing = T)#having a working experience of 90+ is impossible
df = df[seniority<30,]#removing outliers

############################headcount data frame

time_line = seq(as.Date('2011/1/24'),as.Date('2015/12/13'),by = 1)
company = unique(company_id)
headcount = merge(time_line,company,by =NULL) 
#cross join the time line and the company id.
names(headcount)[1] = 'date'
names(headcount)[2] = 'company_id'
headcount = headcount[order(headcount$company_id,headcount$date),]
#order by date and company id in an ascending order

###########################number of people join/quit each day and company

num_join = df %>% group_by(join_date,company_id) %>% 
  summarise(join_count = length(employee_id)) %>%
  arrange(join_date,company_id)
num_join

num_quit = df %>% group_by(quit_date,company_id) %>% 
  summarise(join_count = length(employee_id))%>%
  arrange(quit_date,company_id)
num_quit

###########################join dataframes & data manipulation

headcount = merge(headcount,num_join,
                    by.x = c('date','company_id'),by.y = c('join_date','company_id'),
                    all.x = T)
headcount = merge(headcount,num_quit,
                 by.x = c('date','company_id'),by.y = c('quit_date','company_id'),
                 all.x = T)

names(headcount)[3] = 'join' #rename column names
names(headcount)[4] = 'quit'
headcount$join[is.na(headcount$join)] = 0#replace na values with 0
headcount$quit[is.na(headcount$quit)] = 0

###########################headcount group by company using tapply and cumsum

headcount$join_sum = as.numeric(unlist(tapply(headcount$join, 
                                   INDEX = headcount$company_id, FUN = cumsum)))
headcount$quit_sum = as.numeric(unlist(tapply(headcount$quit, 
                                   INDEX = headcount$company_id, FUN = cumsum)))
headcount$employee_headcount = headcount$join_sum - headcount$quit_sum
headcount = headcount[,c(1,2,7)] #final version

###########################Feature engineering
op = par(mfrow=c(2, 2))
plot(headcount[headcount$company_id ==1,c(1,3)],type = 'l',xlab = 'date',ylab = 'headcount',main = 'headcount_cpn1')
plot(headcount[headcount$company_id ==3,c(1,3)],type = 'l',xlab = 'date',ylab = 'headcount',main = 'headcount_cpn3')
plot(headcount[headcount$company_id ==5,c(1,3)],type = 'l',xlab = 'date',ylab = 'headcount',main = 'headcount_cpn5')
plot(headcount[headcount$company_id ==7,c(1,3)],type = 'l',xlab = 'date',ylab = 'headcount',main = 'headcount_cpn7')
#four random companies headcount plot over the course of 5 years
#There is an indication of another seansonality where employees tend
#to quit in the beginning of the year. Additionally, companies have less
#employee retention over the year and/or tend to hire less employees.

op2 = par(mfrow=c(2, 2))
plot(headcount[(headcount$company_id ==1)&
                 (headcount$date<as.Date('2012-01-01')),c(1,3)],type = 'l',
     xlab = 'date',ylab = 'headcount',main = 'headcount_cpn1')
plot(headcount[(headcount$company_id ==3)&
                 (headcount$date<as.Date('2012-01-01')),c(1,3)],type = 'l',
     xlab = 'date',ylab = 'headcount',main = 'headcount_cpn3')
plot(headcount[(headcount$company_id ==5)&
                 (headcount$date<as.Date('2012-01-01')),c(1,3)],type = 'l',
     xlab = 'date',ylab = 'headcount',main = 'headcount_cpn5')
plot(headcount[(headcount$company_id ==7)&
                 (headcount$date<as.Date('2012-01-01')),c(1,3)],type = 'l',
     xlab = 'date',ylab = 'headcount',main = 'headcount_cpn7')
#four random companies headcount plot over the course of 1 year
#There is an indication of another seansonality where employees tend
#to quit in the middle of the year
par(mfrow=c(1,1))
df$hiring_length = as.numeric(df$quit_date-df$join_date)
hist(df$hiring_length,breaks = 200,xlab = 'hiring_length',ylab = 'frequency',main = 'hiring_length') #seasonality

df$quitweek = as.numeric(strftime(df$quit_date,format = '%U'))
hist(df$quitweek,breaks = 53,,xlab = 'wk_of_yr',ylab = 'frequency',main = 'quit_week')#beginning of the year and middle of the year

df$now = df$quit_date 
df$now[is.na(df$now)] = as.Date('2015-12-15')
df$hiring_length = as.numeric(df$now-df$join_date)
#if quit then quit_date-join_date, if not '2015-12-15'-join_date, 
#'2015-12-15'indicates the present time

df$if_quit = 1
df$if_quit[is.na(df$quit_date)]=0


##########################Random Forest
####################prediciton on if an employee is going to quit

library(randomForest)
set.seed(1)
train = sample(1:nrow(df),nrow(df)*2/3)
df_temp = df[,c(2,3,4,5,8,11)]
df_temp$if_quit = as.factor(df_temp$if_quit)
rf.quit = randomForest(if_quit~.,data = df_temp,subset = train,
                       mtry = 4,importance = TRUE)

quit_pred_rf = predict(rf.quit,df_temp[-train,])

varImpPlot(rf.quit) 

table(quit_pred_rf,df_temp[-train,]$if_quit)
mean(quit_pred_rf==df_temp[-train,]$if_quit)#error rate 16.3%, need tuning

################################# tuning process for mtry

trControl = trainControl(method = "cv",number = 5,search = "grid")
#cross validation to control the training process
tuneGrid = expand.grid(.mtry = c(1: 5))

rf.quit_tune = train(if_quit~.,
                    data = df_temp,
                    method = "rf",
                    metric = "Accuracy",
                    trControl = trControl,
                    tuneGrid = tuneGrid,
                    importance = TRUE)
rf.quit_tune #Accuracy 0.744
#The final value used for the model was mtry = 5.

#################################tuning for ntree
store_ntree = list()
tuneGrid = expand.grid(.mtry = 5)
for(ntree in c(100,200,300,400,500,600,700,800)){
  set.seed(2)
  rf.quit_tune_2 = train(if_quit~.,
                       data = df_temp,
                       method = "rf",
                       metric = "Accuracy",
                       trControl = trControl,
                       tuneGrid = tuneGrid,
                       ntree = ntree,
                       importance = TRUE)
  key = toString(ntree)
  store_ntree[[key]] = rf.quit_tune_2
}
store_ntree = resamples(store_ntree)
summary(store_ntree)#optimal ntree is 700

############################optimal version random forest model

rf.quit_optimal = randomForest(if_quit~.,data = df_temp,subset = train,
                       mtry = 5,ntree = 700,importance = TRUE)

varImpPlot(rf.quit) #hiring length has the highest marginal effect on prediction

quit_pred_rf_optimal = predict(rf.quit_optimal,df_temp[-train,])

table(quit_pred_rf_optimal,df_temp[-train,]$if_quit)
mean(quit_pred_rf_optimal==df_temp[-train,]$if_quit)# error rate 12.1%

#############################Boosted trees

set.seed(1)
df_temp$if_quit = as.character(df_temp$if_quit)
boosted.quit = gbm(if_quit~.,data = df_temp[train,], n.trees  = 5000, 
                   distribution = 'bernoulli',
                   interaction.depth = 4, 
                   shrinkage = 0.1, verbose = T)
summary(boosted.quit)
quit_pred_boosted = predict(boosted.quit,df[-train,],n.trees = 5000)
boosted_quit= rep(0,nrow(df[-train,]))
boosted_quit[quit_pred_boosted>0.5]=1
table(boosted_quit,df[-train,]$if_quit)
mean(boosted_quit==df[-train,]$if_quit) # error rate is 8.5%
mean((quit_pred_boosted-df[-train,]$if_quit))^2 # test MSE: 0.05

par(mfrow=c(1, 1))
plot(boosted.quit, i = 'hiring_length',xlab = 'hiring_length',ylab = 'importance',main ='partial dependence plot hl' )
plot(boosted.quit, i = 'salary',xlab = 'salary',ylab = 'importance',main ='partial dependence plot slry' )
plot(boosted.quit, i = 'seniority',xlab = 'seniority',ylab = 'importance',main ='partial dependence plot snty' )
plot(boosted.quit, i = 'dept',ylab = 'importance',main ='partial dependence plot dept' )
#CONCLUSION: after comparing boosted trees and tuned random forest
#although both are rather accurate, the boosted trees model has
#slight edge on accuracy. 
#SUGGESTION: hiring length and salary is the main factor drive 
#employees to quit and leave. Reasonably, company always has more 
#budget to hire new staff and people tend to have a clear cut off 
#point when they plan to leave in their mind, for example, one year 
#or one year and half seems to be the good period of time for people 
#to age and feel the company culture. Additionally, employees at customer
#service seems to have a rather strong motivation to leave, whereas
#employees at data science dept tend to have longer retention, although
#dept has relatively lower marginal effect.