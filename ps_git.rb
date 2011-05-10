#!/usr/bin/env ruby

require 'fastercsv'
require 'grit'
require 'optparse'
require 'yaml'

# monkey patch to store Hashes in YAML with ordered keys
class Hash
  def to_yaml( opts = {} )
    YAML::quick_emit( object_id, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        sorted_keys = keys
        sorted_keys = begin
          sorted_keys.sort
        rescue
          sorted_keys.sort_by {|k| k.to_s} rescue sorted_keys
        end

        sorted_keys.each do |k|
          map.add( k, fetch(k) )
        end
      end
    end
  end
end

# use this row separator when specifying PowerSchool Quick Export
MAGIC_ROW_SEP = "`'`"

# use these fields in PowerSchool Quick Export
ALL_FIELD_LIST = %w{
  acceptable_use
  alert_discipline
  alert_disciplineexpires
  alert_guardian
  alert_guardianexpires
  alert_hearing
  alert_hearingexpires
  alert_iep
  alert_iepexpires
  alert_life_threatening
  alert_medical
  alert_medicalexpires
  alert_medical_treatment
  alert_other
  alert_otherexpires
  alert_vision
  alert_visionexpires
  allergies
  allergies_benadryl
  allergies_drugs
  allergies_epi_pen
  allergies_food
  allergies_insects
  allergies_other
  allergies_severe
  allowwebaccess
  asthma
  asthma_inhaler
  asthma_medication
  behavior_issues
  behavior_problems
  ca_birthcountry
  ca_birthplace_city
  ca_birthplace_stateprovince
  ca_firstusaschooling
  ca_immigrantfunding
  ca_parented
  ca_primarylanguage
  city
  custody_orders
  dental_carrier
  dental_policy
  dentist_name
  dentist_phone
  diabetes
  diabetes_insulin
  districtentrydate
  dob
  doctor2_name
  doctor2_phone
  doctor_name
  doctor_phone
  electives_6_pa
  electives_7_band
  electives_7_choir
  electives_8_band
  electives_8_choir
  electives_8_enrich1
  electives_8_enrich2
  electives_8_enrich3
  emerg_1_alt_phone
  emerg_1_alt_ptype
  emerg_1_first
  emerg_1_ptype
  emerg_1_rel
  emerg_2_alt_phone
  emerg_2_alt_ptype
  emerg_2_first
  emerg_2_ptype
  emerg_2_rel
  emerg_3_alt_phone
  emerg_3_alt_ptype
  emerg_3_first
  emerg_3_last
  emerg_3_phone
  emerg_3_ptype
  emerg_3_rel
  emerg_contact_1
  emerg_contact_2
  emerg_phone_1
  emerg_phone_2
  emergency_hospital
  emergency_meds
  entrycode
  entrydate
  exitcode
  exitcomment
  exitdate
  eyeglasses
  eyeglasses_always
  eyeglasses_board
  eyeglasses_reading
  father
  father2_cell
  father2_email
  father2_first
  father2_home_phone
  father2_isguardian
  father2_last
  father2_rel
  father2_staff_id
  father2_work_phone
  father_cell
  father_email
  father_first
  father_home_phone
  father_isguardian
  father_rel
  father_staff_id
  father_work_phone
  fedethnicity
  fedracedecline
  first_name
  form1_updated_at
  form1_updated_by
  form2_updated_at
  form2_updated_by
  form3_updated_at
  form3_updated_by
  form4_updated_at
  form4_updated_by
  form5_updated_at
  form5_updated_by
  form6_updated_at
  form6_updated_by
  form7_updated_at
  form7_updated_by
  form8_updated_at
  form8_updated_by
  form9_updated_at
  form9_updated_by
  forme_updated_at
  forme_updated_by
  gender
  guardianemail
  h_hearing_aid
  h_last_eye_exam
  health_ins_type
  home2_city
  home2_id
  home2_no_inet_access
  home2_phone
  home2_printed_material
  home2_spanish_material
  home2_state
  home2_street
  home2_zip
  home_id
  home_no_inet_access
  home_phone
  home_printed_material
  home_room
  home_spanish_material
  homeroom_teacher
  homeroom_teacherfirst
  id
  illness_desc
  illness_recent
  lang_adults_primary
  lang_earliest
  lang_other
  lang_spoken_to
  last_name
  lives_with_rel
  mailing2_city
  mailing2_state
  mailing2_street
  mailing2_zip
  mailing_city
  mailing_state
  mailing_street
  mailing_zip
  medi_cal_num
  medical_accom
  medical_accom_desc
  medical_carrier
  medical_considerations
  medical_other
  medical_policy
  middle_name
  mother
  mother2_cell
  mother2_email
  mother2_first
  mother2_home_phone
  mother2_isguardian
  mother2_last
  mother2_rel
  mother2_staff_id
  mother2_work_phone
  mother_cell
  mother_email
  mother_first
  mother_home_phone
  mother_isguardian
  mother_rel
  mother_staff_id
  mother_work_phone
  movement_limits
  movement_limits_desc
  network_id
  network_password
  optical_carrier
  optical_policy
  prev_school_permission
  previous_school_address
  previous_school_city
  previous_school_grade_level
  previous_school_name
  previous_school_phone
  pub_waiver_public
  pub_waiver_restricted
  reg_grade_level
  reg_previous_celdt
  reg_prog_504
  reg_prog_eld
  reg_prog_gate
  reg_prog_other
  reg_prog_rsp
  reg_prog_sdc
  reg_prog_speech
  reg_will_attend
  release_authorization
  requires_meds
  responsibility_date
  responsibility_signed
  school_meds
  schoolentrydate
  schoolid
  seizures
  seizures_medication
  sibling1_dob
  sibling1_name
  sibling2_dob
  sibling2_name
  sibling3_dob
  sibling3_name
  sibling4_dob
  sibling4_name
  signature_1
  signature_2
  state
  state_studentnumber
  street
  student_number
  vol_first
  vol_help
  vol_last
  vol_phone
  vol_qualifications
  web_id
  web_password
  zip
}

REPO_DIR = File.expand_path(File.dirname(__FILE__), 'repo')

class Gittr
  def initialize(repo_dir)
    @repo_dir = repo_dir
  end
  
  def update
    repo = Grit::Repo.new(@repo_dir)
    Dir.chdir(@repo_dir)

    # Add new or changed files
    status = repo.status
    new_files = status.files.map { |name, sf| sf.untracked ? sf.path : nil }.compact
    changed_files =status.files.map { |name, sf| sf.type == 'M' ? sf.path : nil }.compact
    puts "new files: #{new_files.join(', ')}"
    puts "changed files: #{changed_files.join(', ')}"
    repo.add(new_files)
    repo.add(changed_files)

    # Commit changes
    puts "committing all new or changed files"
    repo.commit_index(Time.now.to_s)
  end
  
  def find_commits(repo, cmdline_opts)
    options = { :max_count => 10, :skip => 0 }
    [:max_count, :since].each do |opt|
      options[opt] = cmdline_opts[opt] if cmdline_opts.key?(opt)
    end
    puts "Options: #{options.inspect}"
    commits = Grit::Commit.find_all(repo, 'master', options)
    # buggy
    options[:since] ? commits.select { |c| c.date >= options[:since] } : commits
  end
  
  def files_changed(cmdline_opts)
    files = [ ]
    repo = Grit::Repo.new(@repo_dir)
    find_commits(repo, cmdline_opts).each { |c| files += c.stats.files.map { |f| [f[0], c.id, c.date] } }
    files
  end
  
  def lines_changed(cmdline_opts)
    repo = Grit::Repo.new(@repo_dir)
    commits = find_commits(repo, cmdline_opts)
    path = cmdline_opts[:filename]
    b = commits.first # head
    a = commits.last
    a = a.parents.first if a.id == b.id && a.parents.first
    puts "Diffs for #{path}"
    puts " from a <#{a.id}>, committed at #{a.committed_date}"
    puts "   to b <#{b.id}>, committed at #{b.committed_date}"
    file_diff = repo.diff(a.id, b.id, path).first
    file_diff ? file_diff.diff : "No changes"
  end
end

class Mungr
  def initialize(repo_dir, data_file, options)
    @repo_dir = repo_dir
    @data_file = data_file
    @options = options
  end
  
  def process_file
    File.open(@data_file) do |f_in|
      while line = f_in.gets(@options[:row_sep])
        line.chomp!(@options[:row_sep])
        values = line.split(@options[:col_sep]).map { |v| (vs = v.strip).empty? ? nil : vs }
        h = Hash[*@options[:headers].zip(values).flatten]
        sn = h['student_number']
        puts "processing #{sn}"
        File.open(File.join(@repo_dir, "#{sn}.txt"), 'w') do |f_out|
          f_out.write("# Student_Number #{sn}\n")
          f_out.write(h.to_yaml)
        end
      end
    end
  end
end

# Findr stuff parses custom pages and collects all fields in registration forms
FORMS_DIR = '/Users/pz/Projects/_active/powerschool-web/data/custom/web_root/guardian'
BUILT_IN_FIELDS = %w{
  id
  alert_discipline
  alert_disciplineexpires
  alert_guardian
  alert_guardianexpires
  alert_hearing
  alert_hearingexpires
  alert_iep
  alert_iepexpires
  alert_life_threatening
  alert_medical
  alert_medicalexpires
  alert_medical_treatment
  alert_other
  alert_otherexpires
  alert_vision
  alert_visionexpires
  allowwebaccess
  districtentrydate
  dob
  entrycode
  entrydate
  exitcode
  exitcomment
  exitdate
  father2_staff_id
  father_staff_id
  first_name
  gender
  guardianemail
  home2_id
  home_id
  home_room
  homeroom_teacher
  homeroom_teacherfirst
  last_name
  middle_name
  mother2_staff_id
  mother_staff_id
  network_id
  network_password
  schoolentrydate
  schoolid
  state_studentnumber
  student_number
  web_id
  web_password
}

# Finds all the fields on all student regforms
# Appends some other ones we're interested in

# Usage
# fields = Findr.new(FORMS_DIR).parse_fields
# puts fields.join("\n")
# exit

class Findr
  def initialize(forms_dir)
    @forms_dir = forms_dir
  end
  
  def parse_fields
    fields = { }
    Dir.chdir(@forms_dir)
    Dir.glob('regform*.html') do |filename|
      File.open(filename).read.scan(/name=\"\[01\]([^"]+)/) { |f| fields[f.first.downcase] = 1 }
    end
    (fields.keys + BUILT_IN_FIELDS).uniq.sort
  end
end

# Main program

options = { }
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: ps_git.rb [options] command"
  opts.separator ""
  opts.separator "Specific options:"
  opts.on('-f', '--file=FILENAME', "file name (required for lines command)") do |f|
    options[:filename] = f
  end
  opts.on('-s', '--since=DATE', "changes since date (YYYY-MM-DD)") do |s|
    y, m, d = s.split(/-/)
    options[:since] = Time.local(y, m, d)
  end
  opts.separator ""
  opts.separator "Commands:\n    import\n    files\n    lines"
end
optparse.parse!

cmd = ARGV.shift

def usage(optparse)
  puts optparse
  exit
end

case cmd
when 'import'
  options[:filename] ||= 'ps-students.txt'
  Mungr.new(REPO_DIR, options[:filename], :headers => ALL_FIELD_LIST, :row_sep => MAGIC_ROW_SEP, :col_sep => "\t").process_file
  Gittr.new(REPO_DIR).update
when 'files'
  puts "Files changed"
  puts Gittr.new(REPO_DIR).files_changed(options).inspect
when 'lines'
  usage(optparse) unless options[:filename]
  puts "Lines changed"
  puts Gittr.new(REPO_DIR).lines_changed(options)
else
  usage(optparse)
end
