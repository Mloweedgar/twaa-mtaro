class SidewalksController < ApplicationController
  respond_to :json
  # added :update in except for testing only, TO BE REMOVED
  before_filter :authenticate_user!, :except => [:index, :find_closest, :update]

  def index
    # check for the type of drains to query
    if params.has_key?(:type)
      if params[:type] == 'all'
        @sidewalks = Sidewalk.find_all(10000)
      else
        if params[:type] == 'cleaned'
          @sidewalks = Sidewalk.where_custom(:cleared => true)
        elsif params[:type] == 'uncleaned'
          @sidewalks = Sidewalk.where_custom(:cleared => false)
        elsif params[:type] == 'need_help'
          @sidewalks = Sidewalk.where_custom(:need_help => true)
        elsif params[:type] == 'adopted'
          @sidewalks = Sidewalk.where_custom_conditions(:claims_count, "> 0")
        elsif params[:type] == 'not_adopted'
          @sidewalks = Sidewalk.where_custom_conditions(:claims_count, "= 0")
        elsif params[:type].include? "address"
          values = params[:type].split('=')
          value = values[1]
          @sidewalks = Sidewalk.where_custom(:gid => value)
        end
      end

      unless @sidewalks.blank?
        respond_with(@sidewalks) do |format|
          format.kml {render}
        end
      else
        render :json => {:errors => {:address => [t("errors.not_found", :thing => t("defaults.thing"))]}}, :status => 404
      end
    else
      @sidewalks = Sidewalk.find_closest(params[:lat], params[:lng], params[:limit] || 10000)
      #puts "#{@sidewalks.size} sidewalks found for [#{params[:lat]}, #{params[:lng]}]"
      unless @sidewalks.blank?
        respond_with(@sidewalks) do |format|
          format.kml {render}
        end
      else
        render :json => {:errors => {:address => [t("errors.not_found", :thing => t("defaults.thing"))]}}, :status => 404
      end
    end
  end

  def find_closest
    gc = Address.geocode("#{params[:address]}, #{params[:city_state]}")

    render :json => {:errors => {:address => [t("errors.not_found", :thing => t("defaults.thing"))]}}, :status => 404 unless (gc && gc.success && gc.street_address)

    unless (sidewalk = Sidewalk.find_by_address(gc.street_address.upcase))
      sidewalk = Sidewalk.find_closest(gc.lat, gc.lng, 1, 0.02).first
    end
    render :json => {:gid => sidewalk ? sidewalk.gid : nil, :lat => gc.lat, :lng => gc.lng}
  end

  def update
    shoveled = (params.fetch(:shoveled, nil) == 'true' ? true : false)
    need_help = (params.fetch(:need_help, nil) == 'true' ? true : false)

    sidewalk = Sidewalk.find_by_gid(params[:id])
    sms_service = SmsService.new()
    user = current_user

    claim = sidewalk.claims.find_by_user_id(user.id)

    if params.has_key?(:shoveled)

      status = (shoveled ? [t("messages.clear_status")] : [t("message.dirt_status")])
      if(user.role == 1)
        if not claim
          render :json => {:errors => {:address => [t("errors.not_found", :thing => t("defaults.thing"))]}}, :status => 404 
        else
          claim.update_attribute(:shoveled, shoveled)
          claim.save(validate: false)
          street_leader = User.find_by_role_and_street_id(2, user.street_id)

          reply_street_leader = "#{user.first_name} #{user.last_name} "\
                              "amewekea alama ya mtaro namba #{sidewalk.gid}"\
                              "kuwa #{status}"
          notify_user = "Umefanikiwa kubadilisha alama ya mtaro wako,"\
                      "namba #{sidewalk.gid} kuwa #{status}"
          sms_service.send_sms(
            reply_street_leader, 
            street_leader.sms_number);
          sms_service.send_sms(
            notify_user, 
            user.sms_number);
        end

      else

        sidewalk.cleared = shoveled
        sidewalk.need_help = false if shoveled
        sidewalk.save(validate: false)

        claim = SidewalkClaim.find_by_gid(sidewalk.gid)

        reply_street_leader = "Umeuwekea alama ya mtaro namba #{sidewalk.gid} "\
                              "kuwa #{status.to_s}"
        sms_service.send_sms(
          reply_street_leader, 
          user.sms_number);

        if claim
          normal_user = User.find_by_id(claim.user_id)
          notify_user = "Kiongozi wa mtaa amebadilisha alama ya mtaro wako,"\
                      "namba #{sidewalk.gid} kuwa #{status.to_s}"
          sms_service.send_sms(
          notify_user, 
          normal_user.sms_number);
        end     
        
      end

    elsif params.has_key?(:need_help)
      sidewalk.update_attribute(:need_help, need_help)
    end

    redirect_to :controller => :sidewalk_claims, :action => :show, :id => params[:id]
  end


end
