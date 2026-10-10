# load data
bgq_dist<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/bgq_dist_16384.data")
bgq_glb<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/bgq_glb_16384.data")


pdf("../bgq_workload.pdf");
par(mfrow=c(1,2));
# draw dist workload
mean_dist=mean(k_dist);
sd_dist=sd(k_dist);
xlab_txt=sprintf("Places(0..16383), mean:%.3f, sd:%.3f", mean_dist, sd_dist);
barplot(bgq_dist, main="BC", xlab=xlab_txt, ylab="Execution time per place", xlim=c(0,16383), ylim=c(0,70));
# draw glb workload
mean_glb=mean(k_glb)
sd_glb=sd(k_glb)
xlab_txt=sprintf("Places(0..16383) \n, mean:%.3f, sd:%.3f", mean_glb, sd_glb);
xlab_txt=sprintf("Places(0..16383), mean:%.3f, sd:%.3f", mean_glb, sd_glb);
barplot(bgq_glb, main="BC-G", xlab=xlab_txt, ylab="Execution time per place", xlim=c(0,16383), ylim=c(0,70));
dev.off()

 
