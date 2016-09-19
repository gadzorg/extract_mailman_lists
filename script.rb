#!/usr/bin/env ruby
# encoding: utf-8
require 'csv'
require 'byebug'
require 'mysql2'

ROOT=File.dirname(__FILE__)
require File.expand_path('./extra_config.rb',ROOT)
CONFIG=ExtraConfig.new(File.expand_path("config.yml",ROOT),"EXPORTLIST")

@lists=Dir[File.join(ROOT,"IN/lists_configs","*")].map{|f|File.basename(f)}


def parse_config_file(list_name,content)
    name = list_name
    mailman_email= "#{list_name}+post@lists.gadz.org"

    real_name=content.match(/real_name = '(.*)'/)[1]

    reply_to_address_raw = content.match(/reply_to_address = '(.*)'/)[1]
    reply_to_address = reply_to_address_raw == '' ? nil : reply_to_address_raw

    description_match=content.match(/description =(.*?)(("""(.*?)""")|'(.*?)')/m)
    description=description_match[4]||description_match[5]

    welcome_msg_match=content.match(/welcome_msg =(.*?)(("""(.*?)""")|'(.*?)')/m)
    welcome_msg=welcome_msg_match[4]||welcome_msg_match[5]

    goodbye_msg_match=content.match(/goodbye_msg =(.*?)(("""(.*?)""")|'(.*?)')/m)
    goodbye_msg=goodbye_msg_match[4]||goodbye_msg_match[5]

    max_message_size = content.match(/max_message_size = ([0-9]+)/)[1].to_i*1000

    msg_header_match =content.match(/msg_header =(.*?)(("""(.*?)""")|'(.*?)')/m)
    msg_header=(msg_header_match[4]||msg_header_match[5]).gsub('%(real_name)s',real_name)

    msg_footer_match =content.match(/msg_footer =(.*?)(("""(.*?)""")|'(.*?)')/m)
    msg_footer=(msg_footer_match[4]||msg_footer_match[5]).to_s.gsub('%(real_name)s',real_name)

    # generic_nonmember_action :
    #   false => public pour les non membres
    #   true  => modéré pour les non membres
    g_nm_a_string = (content.match(/generic_nonmember_action = (.*)/)||["0","0"])[1]
    generic_nonmember_action=(g_nm_a_string == "False" ? false : (g_nm_a_string == "True" ? true : (g_nm_a_string.to_i > 0) ) )

    # default_member_moderation :
    #   false => ok pour les non membres
    #   true  => modéré pour les membres
    d_m_m_string = (content.match(/default_member_moderation = (.*)/)||["0","0"])[1]
    default_member_moderation=(d_m_m_string == "False" ? false : (d_m_m_string == "True" ? true : (d_m_m_string.to_i > 0) ) )

    # !generic_nonmember_action                              => open
    # generic_nonmember_action && !default_member_moderation => closed
    # generic_nonmember_action && default_member_moderation  => moderated
    diffusion_policy= generic_nonmember_action ? (default_member_moderation ? :moderated : :closed) : :open

    subscription_policy= ((content.match(/subscribe_policy = (.*)/)||["0","0"])[1].to_i>0) ? :closed : :conditional_gadz

    return {
      mailman_name:list_name,
      mailman_email: mailman_email,
      email: retrieve_aliases_for(mailman_email).first && retrieve_aliases_for(mailman_email).first['email'],
      name: real_name,
      description: description,
      welcome_msg: welcome_msg,
      goodbye_msg: goodbye_msg,
      max_message_size: max_message_size,
      msg_header: msg_header,
      msg_footer: msg_footer,
      diffusion_policy: diffusion_policy,
      inscription_policy: subscription_policy,
      custom_reply_to: reply_to_address
    }
end

def list_infos_from_config_files
  @lists_infos={}

  @lists.each do |list_name|
    file=File.open(File.join(ROOT,"lists_configs",list_name))
    content=file.read

    @lists_infos[list_name] = parse_config_file(list_name,content)
  end
  @lists_infos
end

def retrieve_aliases_for(email)
  mysql_conn.query('SELECT CONCAT(ev.email,"@",evd.name) AS email FROM email_virtual as ev INNER JOIN email_virtual_domains AS evd ON ev.domain = evd.id WHERE redirect="'+email+'"').to_a
end

def mysql_conn
  @conn||= Mysql2::Client.new(
    :host => CONFIG[:mysql_host],
    :port => CONFIG[:mysql_port],
    :username => CONFIG[:mysql_user],
    :password => CONFIG[:mysql_pass],
    :database => CONFIG[:mysql_db]
    )
end



  @lists_data=list_infos_from_config_files
  members_raw=CSV.parse(File.read(File.expand_path("IN/lists_members",ROOT)),headers: true)
  @members=[]
  members_raw.each do |m|
    if @lists_data[m['list']] && @lists_data[m['list']][:email]
      @members << {'list_email' => @lists_data[m['list']][:email] , 'member_email' => m['email'] }
    else
      p m.to_h
    end
  end

  @lists=@lists_data.select{|k,v| v[:email]}


  CSV.open(File.expand_path("OUT/ml_list-#{Time.now.utc.iso8601.gsub(/\W/, '')}.csv",ROOT), "wb") do |csv|
    csv << @lists.values.first.keys # adds the attributes name on the first line
    @lists.values.each do |hash|
      csv << hash.values
    end
  end

  CSV.open(File.expand_path("OUT/ml_members-#{Time.now.utc.iso8601.gsub(/\W/, '')}.csv",ROOT), "wb") do |csv|
    csv << @members.first.keys # adds the attributes name on the first line
    @members.each do |hash|
      csv << hash.values
    end
  end


require 'irb'
IRB.start