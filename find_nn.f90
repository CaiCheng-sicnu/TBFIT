subroutine find_nn(PINPT,PGEOM,NN_TABLE)
   use parameters
   use mpi_setup
   implicit none
   type (poscar)  :: PGEOM
   type (incar)   :: PINPT
   type (hopping) :: NN_TABLE
   type (hopping) :: NN_TABLE_dummy
   character(*), parameter :: func = 'find_nn'
   integer*4, parameter :: max_neighbor = 30
   integer*4   nn, i, j, iorb, jorb, ix, iy, iz, imatrix, jmatrix, max_nn, ii
   integer*4   index_sigma,index_pi,index_delta   !sk param index
   integer*4   index_sigma_scale,index_pi_scale,index_delta_scale ! sk scale param index
   integer*4   index_stoner !stoner param index
   integer*4   index_custom
   integer*4   index_custom_soc
   integer*4   stoner_I_param_index      ! stoner I param index
   integer*4   local_U_param_index      ! local U param index (for example, staggered potential)
   integer*4   plus_U_param_index      ! plus U param index 
   integer*4   index_lambda !soc param index
   integer*4   max_x, max_y, max_z
   real*8    max_nn_dist
   real*8    Rij_(3),pos_i(3), pos_j(3), Dij_, Dij0_
   real*8    R_(3)
   real*8    enorm
   real*8    tij_sk
   real*8    tij_cc
   real*8    onsite_tol, a1(3), a2(3), a3(3)
   integer*4 onsite_param_index
   character*2       param_class
   character*20      soc_type
   integer*4         nn_class
   external enorm
   external tij_sk, tij_cc
   logical  flag_init, flag_use_site_cindex

   flag_init = .true.
   max_nn= PGEOM%n_atom * max_neighbor * PGEOM%max_orb * PGEOM%max_orb
   allocate( NN_TABLE_dummy%i_atom(max_nn)   )
   allocate( NN_TABLE_dummy%j_atom(max_nn)   )
   allocate( NN_TABLE_dummy%i_coord(3,max_nn)  )
   allocate( NN_TABLE_dummy%j_coord(3,max_nn)  )
   allocate( NN_TABLE_dummy%Rij(3,max_nn)    )
   allocate( NN_TABLE_dummy%R  (3,max_nn)    )
   allocate( NN_TABLE_dummy%Dij(max_nn)      )
   allocate( NN_TABLE_dummy%Dij0(max_nn)     )
   allocate( NN_TABLE_dummy%i_matrix(max_nn) )
   allocate( NN_TABLE_dummy%ci_orb(max_nn)   )
   allocate( NN_TABLE_dummy%j_matrix(max_nn) )
   allocate( NN_TABLE_dummy%cj_orb(max_nn)   )
   allocate( NN_TABLE_dummy%p_class(max_nn)  )
   allocate( NN_TABLE_dummy%n_class(max_nn)  )
   if(     PINPT%flag_slater_koster) allocate( NN_TABLE_dummy%sk_index_set(0:6,max_nn) )
   if(     PINPT%flag_slater_koster)           NN_TABLE_dummy%sk_index_set(0,1:max_nn) = -9999d0
   if(.not.PINPT%flag_slater_koster) allocate( NN_TABLE_dummy%cc_index_set(0:3,max_nn) )
   if(.not.PINPT%flag_slater_koster)           NN_TABLE_dummy%cc_index_set(0,1:max_nn) = -9999d0
   allocate( NN_TABLE_dummy%tij(max_nn)      )
   allocate( NN_TABLE_dummy%soc_param_index(max_nn) )

   allocate( NN_TABLE_dummy%site_cindex(PGEOM%n_atom) ) ! this argument will be used only in this routine 'find_nn'
   NN_TABLE_dummy%site_cindex = NN_TABLE%site_cindex

   NN_TABLE_dummy%soc_param_index = 0

   allocate( NN_TABLE%stoner_I_param_index(PGEOM%neig) )
   allocate( NN_TABLE%local_U_param_index(PGEOM%neig) )
   allocate( NN_TABLE%plus_U_param_index(PGEOM%neig) )
   NN_TABLE%stoner_I_param_index = 0
   NN_TABLE%local_U_param_index = 0
   NN_TABLE%plus_U_param_index = 0

   onsite_tol = NN_TABLE%onsite_tolerance
   a1=PGEOM%a_latt(1:3,1)
   a2=PGEOM%a_latt(1:3,2)
   a3=PGEOM%a_latt(1:3,3)

   if(myid .eq. 0) write(6,*)' '
   if(myid .eq. 0) write(6,*)'*- START SETUP NEIGHBOR ATOM PAIR & HOPPING CLASS'

   max_x = PINPT%nn_max(1)
   max_y = PINPT%nn_max(2)
   max_z = PINPT%nn_max(3)

   max_nn_dist = maxval(PGEOM%nn_dist(:))
   nn=0;

 loop_i:do i=1,PGEOM%n_atom
          if(PGEOM%n_orbital(i) .eq. 0) cycle loop_i
          pos_i= PGEOM%a_coord(1,i)*a1(:) + &
                 PGEOM%a_coord(2,i)*a2(:) + &
                 PGEOM%a_coord(3,i)*a3(:)
          do iorb=1,PGEOM%n_orbital(i)
             imatrix= sum( PGEOM%n_orbital(1:i) ) - PGEOM%n_orbital(i) + iorb
            do ix=-max_x,max_x
              do iy=-max_y,max_y
                 do iz=-max_z,max_z
                   
            loop_j:do j=1,PGEOM%n_atom    
                     if(PGEOM%n_orbital(j) .eq. 0) cycle loop_j
                     pos_j= (PGEOM%a_coord(1,j) + ix)*a1(:) + &
                            (PGEOM%a_coord(2,j) + iy)*a2(:) + &
                            (PGEOM%a_coord(3,j) + iz)*a3(:)
                     R_  =  ix * a1(:) + iy * a2(:) + iz * a3(:)
                     Rij_= pos_j - pos_i
                     Dij_=enorm(3,Rij_)
                     if(Dij_ .gt. max_nn_dist) cycle loop_j
                     call get_nn_class(PGEOM, i,j, Dij_, onsite_tol, nn_class, Dij0_)
                     if(nn_class .ne. -9999) then
                       do jorb=1,PGEOM%n_orbital(j)
                         jmatrix= sum( PGEOM%n_orbital(1:j) ) - PGEOM%n_orbital(j) + jorb
                         if(jmatrix .ge. imatrix) then
                             call get_param_class(PGEOM,iorb,jorb,i,j,param_class)
                             nn = nn + 1
                             NN_TABLE_dummy%i_atom(nn)   = i
                             NN_TABLE_dummy%j_atom(nn)   = j
                             NN_TABLE_dummy%i_coord(:,nn)= pos_i
                             NN_TABLE_dummy%j_coord(:,nn)= pos_j
                             NN_TABLE_dummy%Rij(:,nn)    = Rij_(:)
                             NN_TABLE_dummy%R  (:,nn)    = R_  (:)
                             NN_TABLE_dummy%Dij(nn)      = Dij_
                             NN_TABLE_dummy%Dij0(nn)     = Dij0_
                             NN_TABLE_dummy%i_matrix(nn) = imatrix
                             NN_TABLE_dummy%ci_orb(nn)   = PGEOM%c_orbital(iorb,i)
                             NN_TABLE_dummy%j_matrix(nn) = jmatrix
                             NN_TABLE_dummy%cj_orb(nn)   = PGEOM%c_orbital(jorb,j)
                             NN_TABLE_dummy%p_class(nn)  = param_class
                             NN_TABLE_dummy%n_class(nn)  = nn_class
                             if(      PINPT%flag_slater_koster) NN_TABLE_dummy%sk_index_set(0:6,nn)= 0  ! initialize
                             if(.not. PINPT%flag_slater_koster) NN_TABLE_dummy%cc_index_set(0:3,nn)= 0  ! initialize

                             if(nn_class .eq. 0) then

                               !SET ONSITE energies
                               call get_onsite_param_index(onsite_param_index, PINPT, &
                                                           PGEOM%c_orbital(iorb,i),   &
                                                           PGEOM%c_orbital(jorb,j),   &
                                                           PGEOM%c_spec(PGEOM%spec(i)))
                               if(     PINPT%flag_slater_koster) then 
                                 NN_TABLE_dummy%sk_index_set(0,nn)  = onsite_param_index
                                 NN_TABLE_dummy%tij(nn)             = tij_sk(NN_TABLE_dummy,nn,PINPT,onsite_tol,flag_init)
                               elseif(.not.PINPT%flag_slater_koster) then 
                                 if(param_class .eq. 'cc') then
                                   NN_TABLE_dummy%cc_index_set(0,nn)  = onsite_param_index
                                   NN_TABLE_dummy%tij(nn)             = tij_cc(NN_TABLE_dummy,nn,PINPT,onsite_tol,flag_init)
                                 else
                                   NN_TABLE_dummy%tij(nn)             = 0d0
                                 endif
                               endif

                               !SET local potentail
                               if(PINPT%flag_local_charge) then 
                                 call get_local_U_param_index(local_U_param_index, PINPT, nn_class, param_class, PGEOM%c_spec(PGEOM%spec(i)) )
                                 NN_TABLE%local_U_param_index(imatrix)=local_U_param_index
                               endif

                               !SET Hubbard type +U 
                               if(PINPT%flag_plus_U) then
                                 call get_plus_U_param_index(plus_U_param_index, PINPT, nn_class, param_class, PGEOM%c_spec(PGEOM%spec(i)) )
                                 NN_TABLE%plus_U_param_index(imatrix)= plus_U_param_index
                               endif

                               !SET local magnetic moment
                               if(PINPT%flag_collinear .or. PINPT%flag_noncollinear) then
                                 call get_stoner_I_param_index(stoner_I_param_index, PINPT, nn_class, param_class, PGEOM%c_spec(PGEOM%spec(i)) )
                                 NN_TABLE%stoner_I_param_index(imatrix)=stoner_I_param_index
                               endif
                               
                               !SET SOC parameter 
                               if(PINPT%flag_soc) then
                                 if(param_class .eq. 'pp' .or. param_class .eq. 'dd' .or. param_class .eq. 'xx') then
                                   call get_soc_param_index(index_lambda, PGEOM%c_orbital(iorb,i), PGEOM%c_orbital(jorb,j), &
                                                            PGEOM%c_spec(PGEOM%spec(i)), PINPT, param_class )
                                   NN_TABLE_dummy%soc_param_index(nn) = index_lambda

                                 elseif(param_class .eq. 'cc') then

                                   ! in-plane SOC in the lattice model
                                   soc_type = 'lsoc'
                                   call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                       PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                   NN_TABLE_dummy%cc_index_set(2,nn)  = index_custom_soc  ! SOC due to in-plane symmetry breaking

                                   ! out-of-plane SOC in the lattice model => rashba SOC due to out-of-plane symmetry breaking or E_field(z)
                                   soc_type = 'lrashba'
                                   call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                       PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                   if(index_custom_soc .eq. 0) then 
                                     soc_type = 'lR'
                                     call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                       PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                   endif
                                   NN_TABLE_dummy%cc_index_set(3,nn)  = index_custom_soc

                                 endif
                               endif

                             elseif( nn_class .ge. 1) then

                               !SET HOPPING energies
                               if(PINPT%flag_slater_koster) then
                                 
                                 ! CASE: SLATER_KOSTER TYPE HOPPING
                                 flag_use_site_cindex = logical(NN_TABLE%flag_site_cindex(i) .and. NN_TABLE%flag_site_cindex(j))
                                 call get_sk_index_set(index_sigma,index_pi,index_delta, &
                                                       index_sigma_scale,index_pi_scale,index_delta_scale, &
                                                       PINPT, param_class, nn_class, &
                                                       PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), &
                                                       PGEOM%spec(i), PGEOM%spec(j), &
                                                       NN_TABLE%site_cindex(i), NN_TABLE%site_cindex(j), flag_use_site_cindex )
                                 NN_TABLE_dummy%sk_index_set(1,nn)  = index_sigma
                                 NN_TABLE_dummy%sk_index_set(2,nn)  = index_pi
                                 NN_TABLE_dummy%sk_index_set(3,nn)  = index_delta 
                                 NN_TABLE_dummy%sk_index_set(4,nn)  = index_sigma_scale
                                 NN_TABLE_dummy%sk_index_set(5,nn)  = index_pi_scale
                                 NN_TABLE_dummy%sk_index_set(6,nn)  = index_delta_scale

                                 NN_TABLE_dummy%tij(nn)             = tij_sk(NN_TABLE_dummy,nn,PINPT,onsite_tol,flag_init)
                               elseif(.not. PINPT%flag_slater_koster) then ! cc index : custum orbital hopping index
                                 
                                 ! CASE: USER DEFINED CUSTOM HOPPING
                                 if(param_class .eq. 'cc') then
                                   ! SET T_IJ
                                   call get_cc_index_set(index_custom, NN_TABLE_dummy, nn, PINPT, &
                                                         PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)) )
                                   NN_TABLE_dummy%cc_index_set(1,nn)  = index_custom
                                   NN_TABLE_dummy%tij(nn)             = tij_cc(NN_TABLE_dummy,nn,PINPT,onsite_tol,flag_init)

                                   if(PINPT%flag_soc) then

                                     ! in-plane SOC in the lattice model
                                     soc_type = 'lsoc'
                                     call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                         PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                     NN_TABLE_dummy%cc_index_set(2,nn)  = index_custom_soc
       
                                     ! out-of-plane SOC in the lattice model => rashba SOC due to out-of-plane symmetry breaking or E_field(z)
                                     soc_type = 'lrashba'
                                     call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                         PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                     if(index_custom_soc .eq. 0) then 
                                       soc_type = 'lR'
                                       call get_soc_cc_param_index(index_custom_soc, NN_TABLE_dummy, nn, PINPT, &
                                                         PGEOM%c_spec(PGEOM%spec(i)), PGEOM%c_spec(PGEOM%spec(j)), soc_type )
                                     endif
                                     NN_TABLE_dummy%cc_index_set(3,nn)  = index_custom_soc  
                                   endif
                                  
                                 else
                                   NN_TABLE_dummy%tij(nn)             = 0d0
                                 endif
                               endif

                             endif ! nn_class

                         endif
                       enddo !jorb
                     endif
                   enddo loop_j 

                 enddo
              enddo
            enddo !cell

          enddo !iorb
        enddo loop_i

   NN_TABLE%n_neighbor = nn
   if (nn .gt. max_nn) then
     if(myid .eq. 0) write(6,'(A,I8,A,A)')'  !WARN! Total number of Neighbor pair is exeed MAX_NN=100*N_ATOM*MAX_ORB=',max_nn, &
                          ' Exit... Please recompile with larger MAX_NN', func 
     stop
   endif

   allocate( NN_TABLE%i_atom(nn)   )
   allocate( NN_TABLE%j_atom(nn)   )
   allocate( NN_TABLE%i_coord(3,nn))
   allocate( NN_TABLE%j_coord(3,nn))
   allocate( NN_TABLE%Rij(3,nn)    )
   allocate( NN_TABLE%R  (3,nn)    )
   allocate( NN_TABLE%Dij(nn)      )
   allocate( NN_TABLE%Dij0(nn)     )
   allocate( NN_TABLE%i_matrix(nn) )
   allocate( NN_TABLE%ci_orb(nn)   )
   allocate( NN_TABLE%j_matrix(nn) )
   allocate( NN_TABLE%cj_orb(nn)   )
   allocate( NN_TABLE%p_class(nn)  )
   allocate( NN_TABLE%n_class(nn)  )
   if(     PINPT%flag_slater_koster) allocate( NN_TABLE%sk_index_set(0:6,nn)  )
   if(.not.PINPT%flag_slater_koster) allocate( NN_TABLE%cc_index_set(0:3,nn)  )
   allocate( NN_TABLE%tij(nn)      )
   if(     PINPT%flag_load_nntable ) allocate( NN_TABLE%tij_file(nn)          )
   allocate( NN_TABLE%soc_param_index(nn) )

   NN_TABLE%i_atom(1:nn)           = NN_TABLE_dummy%i_atom(1:nn)
   NN_TABLE%j_atom(1:nn)           = NN_TABLE_dummy%j_atom(1:nn)
   NN_TABLE%i_coord(:,1:nn)        = NN_TABLE_dummy%i_coord(:,1:nn)
   NN_TABLE%j_coord(:,1:nn)        = NN_TABLE_dummy%j_coord(:,1:nn)
   NN_TABLE%Rij(:,1:nn)            = NN_TABLE_dummy%Rij(:,1:nn)
   NN_TABLE%R  (:,1:nn)            = NN_TABLE_dummy%R  (:,1:nn)
   NN_TABLE%Dij(1:nn)              = NN_TABLE_dummy%Dij(1:nn)
   NN_TABLE%Dij0(1:nn)             = NN_TABLE_dummy%Dij0(1:nn)
   NN_TABLE%i_matrix(1:nn)         = NN_TABLE_dummy%i_matrix(1:nn)
   NN_TABLE%ci_orb(1:nn)           = NN_TABLE_dummy%ci_orb(1:nn)  
   NN_TABLE%j_matrix(1:nn)         = NN_TABLE_dummy%j_matrix(1:nn)
   NN_TABLE%cj_orb(1:nn)           = NN_TABLE_dummy%cj_orb(1:nn)  
   NN_TABLE%p_class(1:nn)          = NN_TABLE_dummy%p_class(1:nn)
   NN_TABLE%n_class(1:nn)          = NN_TABLE_dummy%n_class(1:nn)
   if(     PINPT%flag_slater_koster) NN_TABLE%sk_index_set(0:6,1:nn) = NN_TABLE_dummy%sk_index_set(0:6,1:nn)
   if(.not.PINPT%flag_slater_koster) NN_TABLE%cc_index_set(0:3,1:nn) = NN_TABLE_dummy%cc_index_set(0:3,1:nn)
   NN_TABLE%tij(1:nn)              = NN_TABLE_dummy%tij(1:nn)
   NN_TABLE%soc_param_index(1:nn)  = NN_TABLE_dummy%soc_param_index(1:nn)

   deallocate( NN_TABLE_dummy%i_atom   )
   deallocate( NN_TABLE_dummy%j_atom   )
   deallocate( NN_TABLE_dummy%i_coord  )
   deallocate( NN_TABLE_dummy%j_coord  )
   deallocate( NN_TABLE_dummy%Rij      )
   deallocate( NN_TABLE_dummy%R        )
   deallocate( NN_TABLE_dummy%Dij      )
   deallocate( NN_TABLE_dummy%Dij0     )
   deallocate( NN_TABLE_dummy%i_matrix )
   deallocate( NN_TABLE_dummy%ci_orb   )
   deallocate( NN_TABLE_dummy%j_matrix )
   deallocate( NN_TABLE_dummy%cj_orb   )
   deallocate( NN_TABLE_dummy%p_class  )
   deallocate( NN_TABLE_dummy%n_class  )
   if(     PINPT%flag_slater_koster) deallocate( NN_TABLE_dummy%sk_index_set )
   if(.not.PINPT%flag_slater_koster) deallocate( NN_TABLE_dummy%cc_index_set )
   deallocate( NN_TABLE_dummy%tij      )
   deallocate( NN_TABLE_dummy%soc_param_index )

   if(myid .eq. 0) write(6,'(A,I8)')'  N_NEIGH:',NN_TABLE%n_neighbor

   if(myid .eq. 0) write(6,*)' '
   if(myid .eq. 0) write(6,*)'*- END SETUP NEIGHBOR ATOM PAIR & HOPPING CLASS' 

return
endsubroutine
subroutine load_nn_table(NN_TABLE, PINPT)
   use parameters, only : hopping, incar, pid_nntable
   use mpi_setup
   implicit none
   type (hopping) :: NN_TABLE
   type (incar  ) :: PINPT
   integer*4         ii
   integer*4         iatom,jatom,mi,mj
   integer*4         i_onsite,i_sig,i_pi,i_del
   integer*4         n_class, i_sigs,i_pis,i_dels
   integer*4         i_lambda,i_stoner,i_localU
   integer*4         i_tij, i_soc, i_rashba
   real*8            tij
   real*8            R(3),D,D0
   character*5       ci,cj,ptype
   logical           flag_soc, flag_slater_koster, flag_local_charge, flag_plus_U, flag_collinear

   flag_soc = PINPT%flag_soc
   flag_slater_koster = PINPT%flag_slater_koster
   flag_local_charge = PINPT%flag_local_charge
   flag_plus_U = PINPT%flag_plus_U
   flag_collinear = PINPT%flag_collinear

   open(pid_nntable, file=PINPT%nnfilenm, status='old')
   read(pid_nntable,*)     ! ignore fist line  

   do ii=1, NN_TABLE%n_neighbor
     if(flag_soc) then

       if(flag_slater_koster) then
         if(flag_local_charge) then
           read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii), i_lambda, i_stoner, i_localU
         else
           read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii), i_lambda, i_stoner
         endif
       else
         if(flag_local_charge) then
           read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class,  NN_TABLE%tij_file(ii), i_soc, i_rashba, i_stoner, i_localU
         else
           read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class,  NN_TABLE%tij_file(ii), i_soc, i_rashba, i_stoner
         endif
       endif

     elseif(.not. flag_soc) then

       if(flag_slater_koster) then
         if(flag_collinear) then
           if(flag_local_charge) then
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii), i_stoner, i_localU
           else
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii), i_stoner
           endif
         else
           if(flag_local_charge) then
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii), i_localU
           else
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_sig, i_pi, i_del, i_sigs, i_pis, i_dels, n_class, NN_TABLE%tij_file(ii)
           endif
         endif
       else
         if(flag_collinear) then
           if(flag_local_charge) then
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class, NN_TABLE%tij_file(ii), i_stoner, i_localU
           else                                                                                                   
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class, NN_TABLE%tij_file(ii), i_stoner
           endif
         else
           if(flag_local_charge) then
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class, NN_TABLE%tij_file(ii), i_localU
           else                                                                                                          
             read(pid_nntable,*)iatom,jatom,R(:),D,D0,mi,ci,mj,cj,ptype,i_onsite, i_tij, n_class, NN_TABLE%tij_file(ii)   
           endif
         endif
       endif
     endif
   enddo

   close(pid_nntable)

return
endsubroutine
subroutine print_nn_table(NN_TABLE, PINPT)
 use parameters, only : hopping, incar, pid_nntable
 use mpi_setup
 implicit none
 type (hopping) :: NN_TABLE
 type (incar  ) :: PINPT
 integer*4  ii, i, i_check
 logical    flag_soc, flag_slater_koster, flag_local_charge, flag_plus_U, flag_collinear

 flag_soc = PINPT%flag_soc
 flag_slater_koster = PINPT%flag_slater_koster
 flag_local_charge = PINPT%flag_local_charge
 flag_plus_U = PINPT%flag_plus_U
 flag_collinear = PINPT%flag_collinear

 open(pid_nntable, file='hopping.dat', status='unknown')
 if(flag_soc) then
   if(flag_slater_koster) then
     write(pid_nntable,'(A,A)',ADVANCE='no')'#   Iatom Jatom         RIJ(x, y, z)           |RIJ|   |RIJ0|(ang)',&
                       ' M_I "ORB_I"   M_J "ORB_J"  param_type e_o  sig   pi  del sig_s pi_s del_s  nn_class  t_IJ(eV)   lambda_i   stoner_i'
   elseif(.not. flag_slater_koster) then
     write(pid_nntable,'(A,A)',ADVANCE='no')'#   Iatom Jatom         RIJ(x, y, z)           |RIJ|   |RIJ0|(ang)',&
                       ' M_I "ORB_I"   M_J "ORB_J"  param_type e_o  t_IJ  nn_class  t_IJ(eV)   lsoc_i  lrashba_i  stoner_i'
   endif
   if(flag_local_charge) then
     write(pid_nntable,'(A)',ADVANCE='no')'   local_U'
   endif
   if(flag_plus_U) then
     write(pid_nntable,'(A)',ADVANCE='no')'    plus_U'
   endif
   write(pid_nntable,'(A)',ADVANCE='yes')' '
 else
   if(flag_slater_koster) then
     write(pid_nntable,'(A,A)',ADVANCE='no')'#   Iatom Jatom         RIJ(x, y, z)           |RIJ|   |RIJ0|(ang)',&
                       ' M_I "ORB_I"   M_J "ORB_J"  param_type e_o  sig   pi  del sig_s pi_s del_s  nn_class  t_IJ(eV)'
   elseif(.not. flag_slater_koster) then
     write(pid_nntable,'(A,A)',ADVANCE='no')'#   Iatom Jatom         RIJ(x, y, z)           |RIJ|   |RIJ0|(ang)',&
                       ' M_I "ORB_I"   M_J "ORB_J"  param_type e_o  t_IJ  nn_class  t_IJ(eV)'
   endif
   if(flag_collinear) then
     write(pid_nntable,'(A)',ADVANCE='no')'   stoner_i'
   endif
   if(flag_local_charge) then
     write(pid_nntable,'(A)',ADVANCE='no')'   local_U'
   endif
   if(flag_plus_U) then
     write(pid_nntable,'(A)',ADVANCE='no')'    plus_U'
   endif
   write(pid_nntable,'(A)',ADVANCE='yes')' '
 endif

 do ii = 1, NN_TABLE%n_neighbor
   if(flag_soc) then
     if(flag_slater_koster) then
       write(pid_nntable,98,ADVANCE='no')NN_TABLE%i_atom(ii)  , NN_TABLE%j_atom(ii), NN_TABLE%Rij(1:3,ii), NN_TABLE%Dij(ii), NN_TABLE%Dij0(ii), &
                                         NN_TABLE%i_matrix(ii), NN_TABLE%ci_orb(ii), NN_TABLE%j_matrix(ii), NN_TABLE%cj_orb(ii),&
                                         NN_TABLE%p_class(ii), NN_TABLE%sk_index_set(0:6,ii), NN_TABLE%n_class(ii), NN_TABLE%tij(ii), &
                                         NN_TABLE%soc_param_index(ii)
     elseif(.not. flag_slater_koster) then
       write(pid_nntable,96,ADVANCE='no')NN_TABLE%i_atom(ii)  , NN_TABLE%j_atom(ii), NN_TABLE%Rij(1:3,ii), NN_TABLE%Dij(ii), NN_TABLE%Dij0(ii), &
                                         NN_TABLE%i_matrix(ii), NN_TABLE%ci_orb(ii), NN_TABLE%j_matrix(ii), NN_TABLE%cj_orb(ii),&
                                         NN_TABLE%p_class(ii), NN_TABLE%cc_index_set(0:1,ii), NN_TABLE%n_class(ii), NN_TABLE%tij(ii), &
                                         NN_TABLE%cc_index_set(2:3,ii)
     endif
     if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
       write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%stoner_I_param_index(NN_TABLE%i_matrix(ii))
     else
       write(pid_nntable,'(8x,I3)',ADVANCE='no')0
     endif
     if(flag_local_charge) then
       if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
         write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%local_U_param_index(NN_TABLE%i_matrix(ii))
       else
         write(pid_nntable,'(8x,I3)',ADVANCE='no')0
       endif
     endif
     if(flag_plus_U) then
       if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
         write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%plus_U_param_index(NN_TABLE%i_matrix(ii))
       else
         write(pid_nntable,'(8x,I3)',ADVANCE='no')0
       endif
     endif
     write(pid_nntable,'(A)',ADVANCE='yes')' ' 
   elseif(.not. flag_soc) then
     if(flag_slater_koster) then
       write(pid_nntable,99,ADVANCE='no')NN_TABLE%i_atom(ii)  , NN_TABLE%j_atom(ii), NN_TABLE%Rij(1:3,ii), NN_TABLE%Dij(ii), NN_TABLE%Dij0(ii), &
                                         NN_TABLE%i_matrix(ii), NN_TABLE%ci_orb(ii), NN_TABLE%j_matrix(ii), NN_TABLE%cj_orb(ii),&
                                         NN_TABLE%p_class(ii), NN_TABLE%sk_index_set(0:6,ii), NN_TABLE%n_class(ii), NN_TABLE%tij(ii)
     elseif(.not. flag_slater_koster) then
       write(pid_nntable,97,ADVANCE='no')NN_TABLE%i_atom(ii)  , NN_TABLE%j_atom(ii), NN_TABLE%Rij(1:3,ii), NN_TABLE%Dij(ii), NN_TABLE%Dij0(ii), &
                                         NN_TABLE%i_matrix(ii), NN_TABLE%ci_orb(ii), NN_TABLE%j_matrix(ii), NN_TABLE%cj_orb(ii),&
                                         NN_TABLE%p_class(ii), NN_TABLE%cc_index_set(0:1,ii), NN_TABLE%n_class(ii), NN_TABLE%tij(ii)
     endif
     if(flag_collinear) then
       if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
         write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%stoner_I_param_index(NN_TABLE%i_matrix(ii))
       else
         write(pid_nntable,'(8x,I3)',ADVANCE='no')0
       endif
     endif
     if(flag_local_charge) then
       if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
         write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%local_U_param_index(NN_TABLE%i_matrix(ii))
       else
         write(pid_nntable,'(8x,I3)',ADVANCE='no')0
       endif
     endif
     if(flag_plus_U) then
       if( (NN_TABLE%i_matrix(ii) .eq. NN_TABLE%j_matrix(ii))  .and. (NN_TABLE%Dij(ii) .lt. NN_TABLE%onsite_tolerance) ) then
         write(pid_nntable,'(8x,I3)',ADVANCE='no')NN_TABLE%plus_U_param_index(NN_TABLE%i_matrix(ii))
       else
         write(pid_nntable,'(8x,I3)',ADVANCE='no')0
       endif
     endif
     write(pid_nntable,'(A)',ADVANCE='yes')' '    
   endif
   i_check = 0
   if(flag_slater_koster) then
     do i = 0, 6
       if(NN_TABLE%sk_index_set(i,ii) .eq. 0) i_check = i_check + 1
     enddo
     if (i_check .eq. 0) then
       if(myid .eq. 0) write(6,'(A)')'  !WARNING! SK-parameter is not set properly! p_class=',NN_TABLE%p_class(ii),' n_class=',NN_TABLE%n_class(ii)
       stop
     endif
   elseif(.not. flag_slater_koster) then
     do i = 0, 3
       if(NN_TABLE%cc_index_set(i,ii) .eq. 0) i_check = i_check + 1
     enddo
     if (i_check .eq. 0) then
       if(myid .eq. 0) write(6,'(A)')'  !WARNING! CC-parameter is not set properly! p_class=',NN_TABLE%p_class(ii),' n_class=',NN_TABLE%n_class(ii)
       stop
     endif
   endif
 enddo

99 format( 1x,I6,I6,3F10.5,2F10.5,I6,3x,A5,I6,3x,A5,6X, A4,2X, 7I5, I6, 3x, F12.5)
97 format( 1x,I6,I6,3F10.5,2F10.5,I6,3x,A5,I6,3x,A5,6X, A4,2X, 2I5, I6, 3x, F12.5)

98 format( 1x,I6,I6,3F10.5,2F10.5,I6,3x,A5,I6,3x,A5,6X, A4,2X, 7I5, I6, 3x, F12.5,3x,I3)
96 format( 1x,I6,I6,3F10.5,2F10.5,I6,3x,A5,I6,3x,A5,6X, A4,2X, 2I5, I6, 3x, F12.5,3x,I3,6x,I3)
 close(pid_nntable)
return
endsubroutine
subroutine set_param_const(PINPT,PGEOM)
   use parameters, only : incar, poscar
   use mpi_setup
   implicit none
   integer*4     i, ii, i_a, i_b
   character*40  dummy
   type(poscar)  :: PGEOM
   type(incar)   :: PINPT

!PINPT%param_const(i,:) i=1 -> is same as
!                       i=2 -> is lower than (.le.) : set maximum bound  ! functionality is not available yet
!                       i=3 -> is lower than (.ge.) : set minimum bound  ! functionality is not available yet
!                       i=4 -> is fixed : not to be fitted, just stay    ! its original value will be stored in PINPT%param_const(i=5,:)

!  allocate( PINPT%param_const(5,PINPT%nparam) )
!  PINPT%param_const(1,:) = 0d0  ! same as 
!  PINPT%param_const(2,:) = 20d0 ! upper bound
!  PINPT%param_const(3,:) =-20d0 ! lower bound
!  PINPT%param_const(4,:) = 0d0  ! fixed 1:true 0:no
!  PINPT%param_const(5,:) = 0d0  ! fixed value
   do i = 1, PINPT%nparam_const

     if( trim(PINPT%c_const(2,i)) .eq. '=' ) then
       dummy = trim(PINPT%c_const(3,i))
       if( dummy(1:1) .eq. 'F' .or. dummy(1:1) .eq. 'f')then  ! check if fixed
         do ii = 1, PINPT%nparam
           if( trim(PINPT%c_const(1,i)) .eq. trim(PINPT%param_name(ii)) ) i_a = ii
         enddo
         PINPT%param_const(4,i_a) = 1d0 !turn on fix the parameter to be remained as the initial guess
         PINPT%param_const(5,i_a) = PINPT%param(i_a) ! save its value to PINPT%param_const(5,i_a)
       else
         do ii = 1, PINPT%nparam
           if( trim(PINPT%c_const(1,i)) .eq. trim(PINPT%param_name(ii)) ) i_a = ii
           if( trim(PINPT%c_const(3,i)) .eq. trim(PINPT%param_name(ii)) ) i_b = ii
         enddo
         PINPT%param_const(1,i_a) = real(i_b)
       endif
       cycle

     elseif( trim(PINPT%c_const(2,i)) .eq. '<=' ) then 

       do ii = 1, PINPT%nparam
         if( trim(PINPT%c_const(1,i)) .eq. trim(PINPT%param_name(ii)) ) i_a = ii
       enddo
       call str2real( trim(PINPT%c_const(3,i)), PINPT%param_const(2,i_a) )
       cycle

     elseif( trim(PINPT%c_const(2,i)) .eq. '>=' ) then

       do ii = 1, PINPT%nparam
         if( trim(PINPT%c_const(1,i)) .eq. trim(PINPT%param_name(ii)) ) i_a = ii
       enddo
       call str2real( trim(PINPT%c_const(3,i)), PINPT%param_const(3,i_a) )
       cycle

     elseif( trim(PINPT%c_const(2,i)) .eq. '==' ) then

       do ii = 1, PINPT%nparam
         if( trim(PINPT%c_const(1,i)) .eq. trim(PINPT%param_name(ii)) ) i_a = ii
       enddo
       PINPT%param_const(4,i_a) = 1d0 !turn on fix the parameter to be remained as the initial guess
       PINPT%param_const(5,i_a) = PINPT%param(i_a) ! save its value to PINPT%param_const(5,i_a)
       cycle

     else
       if(myid .eq. 0) write(6,'(A)')'  !WARNING! parameter constraint is not properly defined. Please check again. Exit...'
       stop
     endif
   enddo

return
endsubroutine
